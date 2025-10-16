#!/bin/bash

################################################################################
# CleanMyMac - Comprehensive macOS Cleanup Script for Developers
# Compatible with macOS Tahoe (26.0.1) and later
# Author: Developer Tool
# Description: Safely cleans caches, logs, and temporary files from macOS
#              with special focus on developer tools (Docker, VSCode, VMware, etc.)
################################################################################

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
DRY_RUN=false
VERBOSE=false
LOG_FILE="$HOME/.cleanup_log_$(date +%Y%m%d_%H%M%S).txt"
DOWNLOADS_AGE_DAYS=30  # Clean downloads older than this
SAFE_MODE=true  # Require confirmations for destructive operations

################################################################################
# Helper Functions
################################################################################

print_header() {
    echo -e "\n${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}  $1"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

get_size() {
    local path="$1"
    if [ -e "$path" ]; then
        du -sh "$path" 2>/dev/null | awk '{print $1}' || echo "0B"
    else
        echo "0B"
    fi
}

get_disk_usage() {
    df -h / | awk 'NR==2 {print $3 " used of " $2 " (" $5 " full)"}'
}

confirm_action() {
    if [ "$SAFE_MODE" = true ] && [ "$DRY_RUN" = false ]; then
        read -p "Proceed with this cleanup? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_warning "Skipped"
            return 1
        fi
    fi
    return 0
}

cleanup_directory() {
    local dir="$1"
    local desc="$2"

    if [ ! -e "$dir" ]; then
        [ "$VERBOSE" = true ] && print_info "Skipping $desc - not found"
        return
    fi

    local size_before=$(get_size "$dir")
    print_info "Cleaning: $desc ($size_before)"

    if [ "$DRY_RUN" = true ]; then
        print_warning "[DRY RUN] Would clean: $dir"
    else
        if rm -rf "$dir" 2>/dev/null; then
            print_success "Cleaned: $desc (freed $size_before)"
            log_message "Cleaned $desc: $size_before"
        else
            print_error "Failed to clean: $desc"
        fi
    fi
}

################################################################################
# Cleanup Functions
################################################################################

cleanup_system_caches() {
    print_header "Cleaning System Caches"

    local caches=(
        "$HOME/Library/Caches"
        "/Library/Caches"
        "$HOME/Library/Logs"
        "/Library/Logs"
        "/System/Library/Caches"
    )

    for cache in "${caches[@]}"; do
        if [ -d "$cache" ]; then
            local size=$(get_size "$cache")
            print_info "Found cache: $cache ($size)"

            if [ "$DRY_RUN" = false ]; then
                if confirm_action; then
                    find "$cache" -type f -atime +3 -delete 2>/dev/null || true
                    print_success "Cleaned: $cache"
                fi
            fi
        fi
    done
}

cleanup_docker() {
    print_header "Cleaning Docker"

    if ! command -v docker &> /dev/null; then
        print_info "Docker not installed, skipping"
        return
    fi

    print_info "Docker cleanup - removing unused images, containers, and volumes"

    if [ "$DRY_RUN" = true ]; then
        print_warning "[DRY RUN] Would run: docker system df"
        docker system df 2>/dev/null || true
    else
        if confirm_action; then
            # Show current usage
            docker system df 2>/dev/null || true

            # Prune everything
            print_info "Removing stopped containers..."
            docker container prune -f 2>/dev/null || true

            print_info "Removing dangling images..."
            docker image prune -f 2>/dev/null || true

            print_info "Removing unused volumes..."
            docker volume prune -f 2>/dev/null || true

            print_info "Removing build cache..."
            docker builder prune -f 2>/dev/null || true

            print_success "Docker cleanup complete"
            docker system df 2>/dev/null || true
        fi
    fi
}

cleanup_vmware() {
    print_header "Cleaning VMware Fusion"

    local vmware_dir="$HOME/Virtual Machines.localized"

    if [ ! -d "$vmware_dir" ]; then
        print_info "VMware Fusion not found, skipping"
        return
    fi

    print_info "Cleaning VMware logs and caches"

    # Clean VMware logs
    find "$vmware_dir" -name "*.log" -type f 2>/dev/null | while read -r logfile; do
        local size=$(get_size "$logfile")
        if [ "$DRY_RUN" = true ]; then
            print_warning "[DRY RUN] Would delete: $logfile ($size)"
        else
            rm -f "$logfile" && print_success "Deleted log: $(basename "$logfile") ($size)"
        fi
    done

    # Clean VMware cache
    local vmware_cache="$HOME/Library/Caches/com.vmware.fusion"
    if [ -d "$vmware_cache" ]; then
        cleanup_directory "$vmware_cache/*" "VMware Fusion cache"
    fi

    print_info "Note: Snapshot cleanup should be done manually through VMware Fusion"
}

cleanup_vscode() {
    print_header "Cleaning VSCode"

    local vscode_dirs=(
        "$HOME/Library/Application Support/Code/Cache"
        "$HOME/Library/Application Support/Code/CachedData"
        "$HOME/Library/Application Support/Code/CachedExtensions"
        "$HOME/Library/Application Support/Code/CachedExtensionVSIXs"
        "$HOME/Library/Application Support/Code/logs"
        "$HOME/.vscode/extensions/.obsolete"
    )

    for dir in "${vscode_dirs[@]}"; do
        if [ -d "$dir" ]; then
            cleanup_directory "$dir" "VSCode - $(basename "$dir")"
        fi
    done
}

cleanup_node() {
    print_header "Cleaning Node.js / npm / yarn"

    # npm cache
    if command -v npm &> /dev/null; then
        print_info "Cleaning npm cache"
        if [ "$DRY_RUN" = false ]; then
            npm cache clean --force 2>/dev/null || true
            print_success "npm cache cleaned"
        else
            print_warning "[DRY RUN] Would run: npm cache clean --force"
        fi
    fi

    # yarn cache
    if command -v yarn &> /dev/null; then
        print_info "Cleaning yarn cache"
        if [ "$DRY_RUN" = false ]; then
            yarn cache clean 2>/dev/null || true
            print_success "yarn cache cleaned"
        else
            print_warning "[DRY RUN] Would run: yarn cache clean"
        fi
    fi

    # pnpm cache
    if command -v pnpm &> /dev/null; then
        print_info "Cleaning pnpm cache"
        if [ "$DRY_RUN" = false ]; then
            pnpm store prune 2>/dev/null || true
            print_success "pnpm cache cleaned"
        else
            print_warning "[DRY RUN] Would run: pnpm store prune"
        fi
    fi
}

cleanup_homebrew() {
    print_header "Cleaning Homebrew"

    if ! command -v brew &> /dev/null; then
        print_info "Homebrew not installed, skipping"
        return
    fi

    print_info "Cleaning Homebrew cache and old versions"

    if [ "$DRY_RUN" = false ]; then
        if confirm_action; then
            brew cleanup -s 2>/dev/null || true
            brew autoremove 2>/dev/null || true
            rm -rf "$(brew --cache)" 2>/dev/null || true
            print_success "Homebrew cleaned"
        fi
    else
        print_warning "[DRY RUN] Would run: brew cleanup"
    fi
}

cleanup_python() {
    print_header "Cleaning Python"

    # pip cache
    if command -v pip3 &> /dev/null; then
        local pip_cache=$(pip3 cache dir 2>/dev/null || echo "$HOME/Library/Caches/pip")
        if [ -d "$pip_cache" ]; then
            local size=$(get_size "$pip_cache")
            print_info "Found pip cache: $size"
            if [ "$DRY_RUN" = false ]; then
                pip3 cache purge 2>/dev/null || rm -rf "$pip_cache"
                print_success "pip cache cleaned"
            fi
        fi
    fi

    # __pycache__ directories
    print_info "Searching for __pycache__ directories..."
    if [ "$DRY_RUN" = false ]; then
        find "$HOME" -type d -name "__pycache__" -not -path "*/Library/*" -exec rm -rf {} + 2>/dev/null || true
        find "$HOME" -type f -name "*.pyc" -not -path "*/Library/*" -delete 2>/dev/null || true
        print_success "__pycache__ directories cleaned"
    else
        local count=$(find "$HOME" -type d -name "__pycache__" -not -path "*/Library/*" 2>/dev/null | wc -l)
        print_warning "[DRY RUN] Would delete $count __pycache__ directories"
    fi
}

cleanup_git() {
    print_header "Cleaning Git Repositories"

    print_info "Running git garbage collection on repositories in $HOME/Code"

    if [ -d "$HOME/Code" ]; then
        find "$HOME/Code" -name ".git" -type d 2>/dev/null | while read -r gitdir; do
            local repo=$(dirname "$gitdir")
            print_info "Processing: $repo"

            if [ "$DRY_RUN" = false ]; then
                (cd "$repo" && git gc --aggressive --prune=now 2>/dev/null) || true
                print_success "Cleaned git repo: $(basename "$repo")"
            else
                print_warning "[DRY RUN] Would run git gc on: $repo"
            fi
        done
    fi
}

cleanup_xcode() {
    print_header "Cleaning Xcode"

    if [ ! -d "/Applications/Xcode.app" ]; then
        print_info "Xcode not installed, skipping"
        return
    fi

    local xcode_dirs=(
        "$HOME/Library/Developer/Xcode/DerivedData"
        "$HOME/Library/Developer/Xcode/Archives"
        "$HOME/Library/Caches/com.apple.dt.Xcode"
    )

    for dir in "${xcode_dirs[@]}"; do
        if [ -d "$dir" ]; then
            local size=$(get_size "$dir")
            print_info "Found: $(basename "$dir") ($size)"
            if [ "$DRY_RUN" = false ]; then
                if confirm_action; then
                    cleanup_directory "$dir" "Xcode - $(basename "$dir")"
                fi
            fi
        fi
    done

    # Old iOS simulators
    print_info "Checking for old iOS simulators..."
    if command -v xcrun &> /dev/null && [ "$DRY_RUN" = false ]; then
        if confirm_action; then
            xcrun simctl delete unavailable 2>/dev/null || true
            print_success "Removed unavailable simulators"
        fi
    fi
}

cleanup_browsers() {
    print_header "Cleaning Browser Caches"

    local browser_caches=(
        "$HOME/Library/Caches/Google/Chrome"
        "$HOME/Library/Caches/com.apple.Safari"
        "$HOME/Library/Caches/Firefox"
        "$HOME/Library/Safari/LocalStorage"
    )

    for cache in "${browser_caches[@]}"; do
        if [ -d "$cache" ]; then
            local browser=$(basename "$(dirname "$cache")")
            local size=$(get_size "$cache")
            print_info "Found $browser cache: $size"

            if [ "$DRY_RUN" = false ]; then
                if confirm_action; then
                    cleanup_directory "$cache" "$browser cache"
                fi
            fi
        fi
    done
}

cleanup_downloads() {
    print_header "Cleaning Old Downloads"

    local downloads_dir="$HOME/Downloads"

    if [ ! -d "$downloads_dir" ]; then
        return
    fi

    print_info "Finding files older than $DOWNLOADS_AGE_DAYS days in Downloads"

    local old_files=$(find "$downloads_dir" -type f -mtime +$DOWNLOADS_AGE_DAYS 2>/dev/null | wc -l)

    if [ "$old_files" -gt 0 ]; then
        print_info "Found $old_files files older than $DOWNLOADS_AGE_DAYS days"

        if [ "$DRY_RUN" = false ]; then
            if confirm_action; then
                find "$downloads_dir" -type f -mtime +$DOWNLOADS_AGE_DAYS -delete 2>/dev/null || true
                print_success "Cleaned old downloads"
            fi
        else
            print_warning "[DRY RUN] Would delete $old_files files"
        fi
    else
        print_info "No old files found in Downloads"
    fi
}

cleanup_trash() {
    print_header "Emptying Trash"

    if [ "$DRY_RUN" = false ]; then
        if confirm_action; then
            rm -rf "$HOME/.Trash/*" 2>/dev/null || true
            print_success "Trash emptied"
        fi
    else
        local size=$(get_size "$HOME/.Trash")
        print_warning "[DRY RUN] Would empty trash ($size)"
    fi
}

cleanup_misc() {
    print_header "Cleaning Miscellaneous"

    # .DS_Store files
    print_info "Removing .DS_Store files..."
    if [ "$DRY_RUN" = false ]; then
        find "$HOME" -name ".DS_Store" -type f -not -path "*/Library/*" -delete 2>/dev/null || true
        print_success "Removed .DS_Store files"
    else
        local count=$(find "$HOME" -name ".DS_Store" -type f -not -path "*/Library/*" 2>/dev/null | wc -l)
        print_warning "[DRY RUN] Would delete $count .DS_Store files"
    fi

    # iOS backups
    local ios_backup_dir="$HOME/Library/Application Support/MobileSync/Backup"
    if [ -d "$ios_backup_dir" ]; then
        local size=$(get_size "$ios_backup_dir")
        print_info "Found iOS backups: $size"
        print_info "Note: Manual deletion recommended - use Finder > Manage Backups"
    fi

    # Mail downloads
    local mail_downloads="$HOME/Library/Mail Downloads"
    if [ -d "$mail_downloads" ]; then
        cleanup_directory "$mail_downloads/*" "Mail Downloads"
    fi

    # Temporary files
    print_info "Cleaning temporary files..."
    if [ "$DRY_RUN" = false ]; then
        sudo rm -rf /tmp/* 2>/dev/null || true
        print_success "Temporary files cleaned"
    fi
}

################################################################################
# Main Script
################################################################################

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

CleanMyMac - Comprehensive cleanup script for macOS developers

OPTIONS:
    -d, --dry-run       Show what would be cleaned without actually cleaning
    -v, --verbose       Show detailed output
    -y, --yes           Skip confirmation prompts (use with caution!)
    -a, --age DAYS      Set age threshold for Downloads cleanup (default: 30)
    -h, --help          Show this help message

EXAMPLES:
    $0 --dry-run        Preview what will be cleaned
    $0 --yes            Run cleanup without prompts
    $0 -d -v            Dry run with verbose output
    $0 -a 60            Clean downloads older than 60 days

EOF
}

main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -y|--yes)
                SAFE_MODE=false
                shift
                ;;
            -a|--age)
                DOWNLOADS_AGE_DAYS="$2"
                shift 2
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done

    # Print banner
    clear
    echo -e "${GREEN}"
    cat << "EOF"
╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║                    CleanMyMac Pro Script                      ║
║              macOS Tahoe Developer Edition                    ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"

    if [ "$DRY_RUN" = true ]; then
        print_warning "DRY RUN MODE - No changes will be made"
    fi

    # Show initial disk usage
    print_header "Initial Disk Usage"
    print_info "$(get_disk_usage)"

    log_message "Cleanup started - Mode: $([ "$DRY_RUN" = true ] && echo "DRY RUN" || echo "LIVE")"

    # Run cleanup functions
    cleanup_system_caches
    cleanup_docker
    cleanup_vmware
    cleanup_vscode
    cleanup_node
    cleanup_homebrew
    cleanup_python
    cleanup_git
    cleanup_xcode
    cleanup_browsers
    cleanup_downloads
    cleanup_trash
    cleanup_misc

    # Show final disk usage
    print_header "Final Disk Usage"
    print_info "$(get_disk_usage)"

    log_message "Cleanup completed"

    print_header "Cleanup Complete!"
    print_success "Log file saved to: $LOG_FILE"

    if [ "$DRY_RUN" = true ]; then
        print_info "This was a dry run. Run without --dry-run to perform actual cleanup."
    fi
}

# Run main function
main "$@"
