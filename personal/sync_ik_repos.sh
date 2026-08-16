#!/usr/bin/env bash
#
# sync_ik_repos.sh — двусторонняя синхронизация зеркал ik_llama.cpp
#
# Репозитории:
#   fork    = L-MORIA/ik_llama.cpp            (публичный форк, эталон публичной части)
#   origin  = ikawrakow/ik_llama.cpp          (upstream, НЕ трогаем)
#   private = L-MORIA/ik_llama.cpp-rtx5060ti-full (ПРИВАТНОЕ зеркало = публичное + personal/)
#
# Приватка НЕ является форком (GitHub не даёт приватные форки публичных),
# это отдельное приватное репо. Слой personal/ НИКОГДА не уходит в публичный форк.
#
# Режимы:
#   to-private   базис private/main + поверх fork/main + personal/  ->  push private:main (fast-forward)
#   to-public    только публичная часть (без personal/) -> push fork:main            (защита утечки)
#   status       рассинхрон fork/main <-> private/main (read-only)
#   verify       наличие personal/ в приватке (read-only)
#
# Опции:
#   --force           не спрашивать подтверждение
#   --force-push      force-with-lease (только для orphan-снимков; по умолчанию to-private = fast-forward)
#
set -euo pipefail

# ---- конфигурация ----
PUBLIC_REMOTE="fork"
PRIVATE_REMOTE="private"
SNAP_BRANCH="private-snapshot"
JUNK_DIRS="github-data"                  # директории-мусор, исключаемые из снимков
JUNK_FILES="nul nvcc_*.txt"              # файлы-мусор по маскам
PERSONAL_LAYER="personal PRIVATE_REPO_README.md"

# Файлы, по которым шмонаем секреты
SCAN_FILES="PRIVATE_REPO_README.md personal/HERMES_INTEGRATION.md personal/PERSONAL_NOTES.md personal/DESKTOP_SHORTCUT.md build_ik_llama.bat run_ik_qwen38.bat"

# ---- помощники ----
log()  { printf '\033[1;34m[sync]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*"; }
err()  { printf '\033[1;31m[err]\033[0m %s\n' "$*" >&2; }

is_ancestor() { git merge-base --is-ancestor "$1" "$2" 2>/dev/null; }

# очистка мусора: директории + файлы по маскам (НЕ трогает personal/)
clean_junk() {
  for d in $JUNK_DIRS; do
    case "$d" in personal*) continue;; esac
    if [ -e "$d" ]; then
      git rm -r -q --cached "$d" 2>/dev/null || true
      rm -rf "$d" 2>/dev/null || true
    fi
  done
  for p in $JUNK_FILES; do
    find . -path ./personal -prune -o -name "$p" -print 2>/dev/null | while read -r f; do
      case "$f" in personal/*) continue;; esac
      git rm -q --cached "$f" 2>/dev/null || true
      rm -f "$f" 2>/dev/null || true
    done
  done
}

# скан секретов по конкретным файлам
scan_secrets() {
  log "скан секретов по: $SCAN_FILES"
  local hits=0
  for f in $SCAN_FILES; do
    [ -f "$f" ] || continue
    if grep -rniE "(ghp_[A-Za-z0-9]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|AKIA[0-9A-Z]{16}|sk-[A-Za-z0-9]{20,}|password\s*[:=]|api[_-]?key\s*[:=]|Bearer\s+[A-Za-z0-9._-]{20,}|C:\\\\Users\\\\User\\\\(AppData|\\.ssh|\\.config|\\.git))" "$f" 2>/dev/null; then
      warn "похоже на секрет в $f"
      hits=$((hits+1))
    fi
  done
  if [ "$hits" -gt 0 ]; then
    err "обнаружены ПОТЕНЦИАЛЬНЫЕ секреты — пуш отменён. Проверьте файлы вручную."
    return 1
  fi
  log "секретов не найдено ✓"
  return 0
}

# снимок-потомок БАЗИСА (remote-tracking ref) + поверх ЭТАЛОН (remote-tracking ref) + слой personal
build_snapshot_ff() {
  local base="$1" src="$2"
  log "сборка снимка: базис=$base, эталон=$src, слой personal/"
  git checkout -q -B "$SNAP_BRANCH" "$base"
  git read-tree "$src"
  git checkout-index -a -f
  # ЛИЧНЫЙ слой берём из ЛОКАЛЬНОГО main (там самые свежие правки personal/),
  # НЕ из $base (private/main), иначе правки personal теряются при каждом снимке
  if git ls-tree -r --name-only main | grep -qE "^personal/"; then
    git checkout -q main -- personal PRIVATE_REPO_README.md 2>/dev/null || true
  fi
  clean_junk
  git add -A
  git commit -q -m "mirror: $(date -u +%Y-%m-%dT%H:%M:%SZ) fork/main + personal" || log "нет изменений — снимок актуален"
}

build_snapshot_orphan() {
  local src="$1"
  log "сборка orphan-снимка из $src + personal/"
  git checkout -q --orphan "$SNAP_BRANCH"
  git read-tree "$src"
  git checkout-index -a -f
  clean_junk
  git add -A
  git commit -q -m "mirror snapshot: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
}

cmd_status() {
  log "статус рассинхрона fork/main <-> private/main"
  local diff
  diff=$(git diff --name-only remotes/$PUBLIC_REMOTE/main remotes/$PRIVATE_REMOTE/main)
  local total junk real
  total=$(echo "$diff" | grep -c . || true)
  junk=$(echo "$diff" | grep -cE "github-data/|/nul$|nvcc_.*\.txt" || true)
  real=$((total - junk))
  echo "  всего отличающихся файлов: $total"
  echo "  из них мусора (github-data/nul/nvcc): $junk"
  echo "  реальный контент (нужно синхронизировать): $real"
  echo "  personal/ в приватке: $(git ls-tree -r --name-only remotes/$PRIVATE_REMOTE/main | grep -cE '^personal/' || echo 0) файлов"
}

cmd_verify() {
  log "проверка наличия personal/ в приватке (read-only)"
  git ls-tree -r --name-only remotes/$PRIVATE_REMOTE/main | grep -E "^personal/" || warn "personal/ НЕ найден в private/main"
  log "готово (read-only)"
}

cmd_to_private() {
  local force_push="${FORCE_PUSH:-0}"
  log "fetch $PUBLIC_REMOTE (обновить эталон)"
  git fetch "$PUBLIC_REMOTE" 2>&1 | tail -2 || true
  scan_secrets || return 1
  build_snapshot_ff "remotes/$PRIVATE_REMOTE/main" "remotes/$PUBLIC_REMOTE/main"
  local base_ref="remotes/$PRIVATE_REMOTE/main"
  if is_ancestor "$base_ref" "$SNAP_BRANCH"; then
    log "push $PRIVATE_REMOTE/main (fast-forward)"
    git push "$PRIVATE_REMOTE" "$SNAP_BRANCH:main"
  elif [ "$force_push" = "1" ]; then
    warn "не fast-forward — force-with-lease"
    git push --force-with-lease "$PRIVATE_REMOTE" "$SNAP_BRANCH:main"
  else
    err "снимок НЕ является наследником private/main. Если нужен пересбор — используйте --force-push."
    return 1
  fi
  git checkout -q main 2>/dev/null || true
  log "✅ приватка обновлена"
}

cmd_to_public() {
  scan_secrets || return 1
  log "сборка ТОЛЬКО публичной части (без personal/) -> $PUBLIC_REMOTE/main"
  build_snapshot_orphan "remotes/$PUBLIC_REMOTE/main"
  git rm -r -q --cached personal PRIVATE_REPO_README.md 2>/dev/null || true
  rm -rf personal PRIVATE_REPO_README.md 2>/dev/null || true
  git add -A
  git commit -q --amend -m "public mirror: $(date -u +%Y-%m-%dT%H:%M:%SZ)" || true
  git push "$PUBLIC_REMOTE" "$SNAP_BRANCH:main" --force-with-lease
  git checkout -q main 2>/dev/null || true
  log "✅ публичный форк обновлен (personal/ исключён)"
}

# ---- CLI ----
FORCE=0
FORCE_PUSH=0
MODE=""
while [ $# -gt 0 ]; do
  case "$1" in
    to-private|to-public|status|verify) MODE="$1" ;;
    --force) FORCE=1 ;;
    --force-push) FORCE_PUSH=1 ;;
    -h|--help) echo "usage: $0 {to-private|to-public|status|verify} [--force] [--force-push]"; exit 0 ;;
    *) err "неизвестный аргумент: $1"; exit 1 ;;
  esac
  shift
done

[ -n "$MODE" ] || { err "режим не задан"; exit 1; }

if [ "$MODE" != "status" ] && [ "$MODE" != "verify" ] && [ "$FORCE" != "1" ]; then
  read -r -p "Выполнить '$MODE'? [y/N] " ans
  case "$ans" in y|Y|yes|YES) ;; *) err "отменено"; exit 1 ;; esac
fi

case "$MODE" in
  status) cmd_status ;;
  verify) cmd_verify ;;
  to-private) cmd_to_private ;;
  to-public) cmd_to_public ;;
esac
