#!/usr/bin/env bash
#
# sync-upstream.sh — keep this fork's `main` a clean mirror of upstream, then
# fold upstream changes into the Unity 2022.3 compatibility branch.
#
# Policy this script enforces (see also the project README / branch notes):
#   1. `main` is a PURE MIRROR of upstream/main. It must never carry local
#      commits, so updating it is a fast-forward ONLY. If the fast-forward
#      fails, main was polluted and the script aborts for you to investigate.
#   2. Unity customizations (C# 9 down-level + UNITY_2022_3_OR_NEWER guards)
#      live ONLY on the compat branch. They are merged in, never rebased.
#   3. After merging upstream, the runtime libraries MUST still compile under
#      LangVersion 9.0 across all TFMs — upstream may introduce C# 10+ syntax.
#      The script runs the Release build and fails loudly if it breaks.
#
# What it automates (the safe parts):
#   fetch upstream -> ff-only update main -> push main
#   -> merge main into the compat branch -> verify the C# 9 Release build
#
# What it deliberately leaves to you (the judgement parts):
#   - resolving merge conflicts (keep the Unity guards + C# 9 down-levels)
#   - down-leveling any new C# 10+ syntax upstream introduced
#   - the FINAL `git push` of the compat branch, so you can review the merge
#
# Usage:  ./scripts/sync-upstream.sh
set -uo pipefail

COMPAT_BRANCH="unity-2022.3-compat"
UPSTREAM_REMOTE="upstream"
ORIGIN_REMOTE="origin"
# Projects that are down-leveled to C# 9 for Unity; these are the ones to verify.
BUILD_PROJECT="src/protobuf-net/protobuf-net.csproj"   # pulls in protobuf-net.Core too

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
die()  { printf '\033[31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

# --- preconditions -----------------------------------------------------------
cd "$(git rev-parse --show-toplevel)" || die "not inside a git repository"

git remote get-url "$UPSTREAM_REMOTE" >/dev/null 2>&1 \
  || die "remote '$UPSTREAM_REMOTE' is not configured. Run:
       git remote add $UPSTREAM_REMOTE https://github.com/protobuf-net/protobuf-net.git"

[ -z "$(git status --porcelain)" ] \
  || die "working tree is dirty. Commit or stash your changes first."

command -v dotnet >/dev/null 2>&1 \
  || die "'dotnet' not found on PATH. Install the SDK pinned in global.json."

START_BRANCH="$(git rev-parse --abbrev-ref HEAD)"

# --- 1. fetch upstream -------------------------------------------------------
bold "==> Fetching $UPSTREAM_REMOTE"
git fetch "$UPSTREAM_REMOTE" --prune || die "git fetch $UPSTREAM_REMOTE failed"

BEHIND="$(git rev-list --count main..$UPSTREAM_REMOTE/main)"
if [ "$BEHIND" -eq 0 ]; then
  bold "==> main is already up to date with $UPSTREAM_REMOTE/main — nothing to sync."
  git checkout "$START_BRANCH" >/dev/null 2>&1 || true
  exit 0
fi
bold "==> $BEHIND new upstream commit(s) to fold in"

# --- 2. update main as a pure mirror (fast-forward only) ---------------------
bold "==> Updating main (fast-forward only)"
git checkout main || die "could not checkout main"
if ! git merge --ff-only "$UPSTREAM_REMOTE/main"; then
  git checkout "$START_BRANCH" >/dev/null 2>&1 || true
  die "main could not fast-forward to $UPSTREAM_REMOTE/main.
       This means main has local commits and is no longer a clean mirror.
       Move any local commits to '$COMPAT_BRANCH' and reset main to upstream:
         git checkout main && git reset --hard $UPSTREAM_REMOTE/main"
fi
git push "$ORIGIN_REMOTE" main || die "failed to push main to $ORIGIN_REMOTE"

# --- 3. merge main into the compat branch ------------------------------------
bold "==> Merging main into $COMPAT_BRANCH"
git checkout "$COMPAT_BRANCH" || die "could not checkout $COMPAT_BRANCH"
if ! git merge --no-edit main; then
  bold "!!! Merge conflicts. Resolve them, KEEPING:"
  echo "      - the UNITY_2022_3_OR_NEWER guards in *AssemblyInfo.cs"
  echo "      - the LangVersion 9.0 block in src/Directory.Build.props"
  echo "    Then finish manually:"
  echo "      git add -A && git commit"
  echo "      dotnet build $BUILD_PROJECT -c Release"
  echo "      git push $ORIGIN_REMOTE $COMPAT_BRANCH"
  die "stopped on merge conflict (intentional — human judgement required)"
fi

# --- 4. verify the C# 9 build still holds ------------------------------------
bold "==> Verifying C# 9 Release build across all TFMs"
if ! dotnet build "$BUILD_PROJECT" -c Release; then
  bold "!!! Build FAILED after merge."
  echo "    Likely upstream introduced C# 10+ syntax (collection expressions,"
  echo "    required members, primary constructors, raw strings, etc.)."
  echo "    Down-level it to C# 9 in the runtime libraries, rebuild, then:"
  echo "      git push $ORIGIN_REMOTE $COMPAT_BRANCH"
  die "C# 9 build broken — fix before pushing (intentional stop)"
fi

# --- 5. done — leave the push to the human -----------------------------------
bold "==> SUCCESS: $COMPAT_BRANCH merged and the C# 9 build is clean."
echo "    Review the merge, then push when satisfied:"
echo "      git push $ORIGIN_REMOTE $COMPAT_BRANCH"
