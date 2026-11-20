#!/usr/bin/env bash
# scripts/bench-baseline-status.sh
#
# Report whether a published benchmark baseline exists for each channel, so
# the PR comparison runs only against a real baseline and says so plainly
# when there is none.
#
# The baseline is the github-action-benchmark history on the `gh-pages`
# branch: `perf/bench/data.js` (smaller-is-better channel) and
# `perf/bench-bigger/data.js` (bigger-is-better channel). It is published
# only by an isolated run on `dev`, so until the first such run there is
# nothing to compare against. That state is reported as a notice and in the
# job summary, and the hard-threshold gate still runs; it is never reported
# as a passed comparison.
#
# Writes `smaller=true|false` and `bigger=true|false` to $GITHUB_OUTPUT.
# Only "not found" (HTTP 404, for the branch or the file) means "no
# baseline". Any other failure to ask is an error, so an auth or network
# problem cannot pass for an empty baseline.
#
# Needs: gh, GH_TOKEN, GITHUB_REPOSITORY, GITHUB_OUTPUT.
set -euo pipefail

: "${GITHUB_REPOSITORY:?}" "${GITHUB_OUTPUT:?}"

probe() {
  # $1 = channel directory on gh-pages. Prints true or false.
  local path="$1/data.js" out rc
  set +e
  out="$(gh api -H 'Accept: application/vnd.github+json' \
    "repos/${GITHUB_REPOSITORY}/contents/${path}?ref=gh-pages" --jq .sha 2>&1)"
  rc=$?
  set -e
  if [ "$rc" -eq 0 ]; then
    echo true
  elif printf '%s' "$out" | grep -q 'HTTP 404'; then
    echo false
  else
    echo "bench-baseline-status: could not determine whether gh-pages:${path} exists: ${out}" >&2
    return 1
  fi
}

smaller="$(probe perf/bench)"
bigger="$(probe perf/bench-bigger)"
printf 'smaller=%s\nbigger=%s\n' "$smaller" "$bigger" >>"$GITHUB_OUTPUT"

for pair in "smaller:perf/bench:${smaller}" "bigger:perf/bench-bigger:${bigger}"; do
  IFS=: read -r channel dir present <<<"$pair"
  if [ "$present" = true ]; then
    echo "bench-baseline-status: ${channel} channel: baseline present at gh-pages:${dir}/data.js; comparing."
  else
    msg="No published ${channel}-is-better baseline yet (gh-pages:${dir}/data.js does not exist). This PR is NOT compared against a baseline on that channel; only the hard-threshold gate applies. The first isolated benchmark run on dev publishes the baseline."
    echo "::notice title=No benchmark baseline (${channel})::${msg}"
    if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
      printf -- '- **No benchmark baseline (%s):** %s\n' "$channel" "$msg" >>"$GITHUB_STEP_SUMMARY"
    fi
  fi
done
