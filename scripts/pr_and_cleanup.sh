#!/bin/bash
set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

# Usage
if [ $# -lt 1 ]; then
    echo "Usage: $0 <feature-name>"
    echo "Example: $0 user-auth"
    exit 1
fi

FEATURE_NAME="$1"

# --- SECURITY: Input Validation ---
# Only allow alphanumeric, hyphens, and underscores. Prevents directory traversal.
if [[ ! "$FEATURE_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    log_error "Invalid feature name. Only alphanumeric, hyphens, and underscores are allowed."
    exit 1
fi

BRANCH_NAME="feature/${FEATURE_NAME}"
WORKTREE_DIR=".worktrees/${FEATURE_NAME}"

# Ensure we are in repo root
REPO_ROOT=$(git rev-parse --show-toplevel)
cd "$REPO_ROOT"

# --- SECURITY: Gitignore Check ---
if ! grep -q ".worktrees" .gitignore 2>/dev/null; then
    log_warn "'.worktrees' is not in .gitignore. You risk committing secrets."
    log_warn "Suggestion: echo '.worktrees/' >> .gitignore"
fi

log_info "Creating worktree: ${FEATURE_NAME}"

# Create Worktree
if [ -d "${WORKTREE_DIR}" ]; then
    log_error "Worktree directory already exists: ${WORKTREE_DIR}"
    exit 1
fi

if git show-ref --verify --quiet "refs/heads/${BRANCH_NAME}"; then
    log_warn "Branch ${BRANCH_NAME} already exists. Attaching to existing branch..."
    git worktree add "${WORKTREE_DIR}" "${BRANCH_NAME}"
else
    log_step "Creating new branch and worktree..."
    git worktree add -b "${BRANCH_NAME}" "${WORKTREE_DIR}" main
fi

# Environment Setup
copy_if_exists() {
    local src="$1"
    local dest="$2"
    if [ -f "${src}" ]; then
        # Ensure parent directory exists
        mkdir -p "$(dirname "${dest}")"
        cp "${src}" "${dest}"
        log_info "Copied: ${src}"
    fi
}

log_step "Configuring environment..."

# Handle root .env with port randomization
if [ -f ".env" ]; then
    RANDOM_FRONTEND_PORT=$((RANDOM % 50000 + 10000))
    RANDOM_BACKEND_PORT=$((RANDOM % 50000 + 10000))
    RANDOM_AGENT_PORT=$((RANDOM % 50000 + 10000))

    # Ensure worktree dir exists before writing
    mkdir -p "${WORKTREE_DIR}"

    sed -e "s/^FRONTEND_PORT=.*/FRONTEND_PORT=${RANDOM_FRONTEND_PORT}/" \
        -e "s/^BACKEND_PORT=.*/BACKEND_PORT=${RANDOM_BACKEND_PORT}/" \
        -e "s/^AGENT_PORT=.*/AGENT_PORT=${RANDOM_AGENT_PORT}/" \
        ".env" > "${WORKTREE_DIR}/.env"

    log_info "Generated .env with isolated ports"
fi

# Copy other env files
copy_if_exists ".envrc" "${WORKTREE_DIR}/.envrc"
FRONTEND_FILES=(".env" ".env.local" ".env.dev" ".env.prd" ".env.test")
for file in "${FRONTEND_FILES[@]}"; do
    copy_if_exists "modules/frontend/${file}" "${WORKTREE_DIR}/modules/frontend/${file}"
done
copy_if_exists "modules/backend/.env" "${WORKTREE_DIR}/modules/backend/.env"
copy_if_exists "modules/agent/.env" "${WORKTREE_DIR}/modules/agent/.env"

# Run Setup
log_step "Running setup..."
cd "${WORKTREE_DIR}"
if [ -f "Makefile" ]; then
    make setup || log_warn "make setup completed with warnings"
else
    log_warn "No Makefile found, skipping setup"
fi

echo ""
echo -e "${GREEN}Worktree Ready!${NC}"
echo "Path:   ${REPO_ROOT}/${WORKTREE_DIR}"
echo "Branch: ${BRANCH_NAME}"
echo "Command: cd ${WORKTREE_DIR}"
