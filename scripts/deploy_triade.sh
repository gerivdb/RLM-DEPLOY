#!/bin/bash
# RLM-DEPLOY/scripts/deploy_triade.sh
# Script de déploiement pour la triade cognitive LLUX + PIANO + SPIDX

set -euo pipefail

# Configuration
TRIX_BIN="/usr/local/bin/trix"
LLUX_BIN="/opt/trix/bin/llux"
PIANO_BIN="/opt/piano/bin/piano"
SPIDX_BIN="/opt/spidx/bin/spidx"
TOKENIZER_MODEL="/opt/trix/models/tokenizer.json"

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# Nettoyage à la sortie
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_error "Déploiement échoué, nettoyage..."
        # Rollback optionnel
    fi
    exit $exit_code
}
trap cleanup EXIT

# Vérifier les prérequis
check_prerequisites() {
    log_info "Vérification des prérequis..."
    
    local missing=()
    
    [[ -f "$TRIX_BIN" ]] || missing+=("TRIX ($TRIX_BIN)")
    [[ -f "$LLUX_BIN" ]] || missing+=("LLUX ($LLUX_BIN)")
    [[ -f "$PIANO_BIN" ]] || missing+=("PIANO ($PIANO_BIN)")
    [[ -f "$SPIDX_BIN" ]] || missing+=("SPIDX ($SPIDX_BIN)")
    [[ -f "$TOKENIZER_MODEL" ]] || missing+=("Tokenizer model ($TOKENIZER_MODEL)")
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Fichiers manquants : ${missing[*]}"
        return 1
    fi
    
    log_success "Prérequis OK"
    return 0
}

# Arrêter les services
stop_services() {
    log_info "Arrêt des services..."
    
    if "$TRIX_BIN" backend status llux 2>/dev/null | grep -q "running"; then
        log_info "Arrêt de LLUX..."
        "$TRIX_BIN" backend stop llux || log_warn "Échec arrêt LLUX"
    fi
    
    log_success "Services arrêtés"
}

# Déployer les binaires
deploy_binaries() {
    log_info "Déploiement des binaires..."
    
    # Backup des binaires actuels
    cp "$LLUX_BIN" "${LLUX_BIN}.backup.$(date +%s)" 2>/dev/null || true
    cp "$PIANO_BIN" "${PIANO_BIN}.backup.$(date +%s)" 2>/dev/null || true
    cp "$SPIDX_BIN" "${SPIDX_BIN}.backup.$(date +%s)" 2>/dev/null || true
    
    # Copier les nouveaux binaires (depuis le répertoire de build)
    local build_dir="${BUILD_DIR:-./zig-out/bin}"
    
    [[ -f "$build_dir/llux" ]] && cp "$build_dir/llux" "$LLUX_BIN" && log_success "LLUX déployé"
    [[ -f "$build_dir/piano" ]] && cp "$build_dir/piano" "$PIANO_BIN" && log_success "PIANO déployé"
    [[ -f "$build_dir/spidx" ]] && cp "$build_dir/spidx" "$SPIDX_BIN" && log_success "SPIDX déployé"
    
    chmod +x "$LLUX_BIN" "$PIANO_BIN" "$SPIDX_BIN"
    
    log_success "Binaires déployés"
}

# Déployer le tokenizer
deploy_tokenizer() {
    log_info "Déploiement du tokenizer..."
    
    if [[ -f "$TOKENIZER_MODEL" ]]; then
        cp "$TOKENIZER_MODEL" "${TOKENIZER_MODEL}.backup.$(date +%s)"
    fi
    
    local build_dir="${BUILD_DIR:-./zig-out/bin}"
    [[ -f "$build_dir/tokenizer.json" ]] && cp "$build_dir/tokenizer.json" "$TOKENIZER_MODEL" && log_success "Tokenizer déployé"
}

# Démarrer les services
start_services() {
    log_info "Démarrage des services..."
    
    log_info "Démarrage de LLUX via TRIX..."
    "$TRIX_BIN" backend start llux
    
    # Attendre que le service soit prêt
    local max_wait=30
    local waited=0
    
    while [[ $waited -lt $max_wait ]]; do
        if curl -sf http://localhost:47000/health >/dev/null 2>&1; then
            log_success "LLUX est prêt"
            return 0
        fi
        sleep 2
        waited=$((waited + 2))
    done
    
    log_error "LLUX n'a pas démarré dans les ${max_wait}s"
    return 1
}

# Vérifier la santé
verify_health() {
    log_info "Vérification de la santé..."
    
    # Health endpoint
    if ! curl -sf http://localhost:47000/health | jq -e '.status == "healthy"' >/dev/null; then
        log_error "Health check échoué"
        return 1
    fi
    log_success "Health check OK"
    
    # Chat endpoint
    local chat_response
    chat_response=$(curl -sf -X POST http://localhost:47000/v1/chat/completions \
        -H "Content-Type: application/json" \
        -d '{"messages":[{"role":"user","content":"test"}],"model":"bitnet-1.58b"}')
    
    if ! echo "$chat_response" | jq -e '.choices' >/dev/null; then
        log_error "Chat endpoint échoué"
        return 1
    fi
    log_success "Chat endpoint OK"
    
    # Embedding endpoint
    local embed_response
    embed_response=$(curl -sf -X POST http://localhost:47000/v1/embeddings \
        -H "Content-Type: application/json" \
        -d '{"input":"test","model":"nomic-embed-v1.5"}')
    
    if ! echo "$embed_response" | jq -e '.data[0].embedding' >/dev/null; then
        log_error "Embedding endpoint échoué"
        return 1
    fi
    log_success "Embedding endpoint OK"
    
    # GATEWAY-MANAGER route
    local gateway_response
    gateway_response=$(curl -sf -X POST http://localhost:9000/mcp/llux/llm/chat \
        -H "Content-Type: application/json" \
        -d '{"messages":[{"role":"user","content":"test"}]}')
    
    if ! echo "$gateway_response" | jq -e '.choices' >/dev/null; then
        log_warn "GATEWAY-MANAGER route non disponible (optionnel)"
    else
        log_success "GATEWAY-MANAGER route OK"
    fi
    
    log_success "Tous les checks de santé passent"
}

# Rollback en cas d'échec
rollback() {
    log_warn "Rollback..."
    
    "$TRIX_BIN" backend stop llux 2>/dev/null || true
    
    local latest_backup
    latest_backup=$(ls -t "${LLUX_BIN}.backup."* 2>/dev/null | head -1)
    [[ -n "$latest_backup" ]] && cp "$latest_backup" "$LLUX_BIN" && log_info "LLUX restauré: $latest_backup"
    
    latest_backup=$(ls -t "${PIANO_BIN}.backup."* 2>/dev/null | head -1)
    [[ -n "$latest_backup" ]] && cp "$latest_backup" "$PIANO_BIN" && log_info "PIANO restauré: $latest_backup"
    
    latest_backup=$(ls -t "${SPIDX_BIN}.backup."* 2>/dev/null | head -1)
    [[ -n "$latest_backup" ]] && cp "$latest_backup" "$SPIDX_BIN" && log_info "SPIDX restauré: $latest_backup"
    
    "$TRIX_BIN" backend start llux 2>/dev/null || true
    
    log_warn "Rollback terminé"
}

# Fonction principale
main() {
    log_info "=== Déploiement Triade Cognitive ==="
    log_info "Date: $(date)"
    log_info "Build dir: ${BUILD_DIR:-./zig-out/bin}"
    
    check_prerequisites || exit 1
    stop_services
    deploy_binaries
    deploy_tokenizer
    start_services
    
    if verify_health; then
        log_success "=== DÉPLOIEMENT RÉUSSI ==="
        exit 0
    else
        log_error "Échec des vérifications, rollback..."
        rollback
        exit 1
    fi
}

# Exécution
main "$@"