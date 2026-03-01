# ---- Stage 1: dependency install ----
# distroless node image for building; minimal OS packages reduce vulnerabilities.
FROM gcr.io/distroless/nodejs22-debian12 AS builder

WORKDIR /app

# package-lock.json (no glob) — lockfile must be present for reproducible,
# integrity-verified installs. npm ci fails if it is missing.
# --ignore-scripts: prevents pre/postinstall scripts from running (supply-chain risk).
COPY package.json package-lock.json ./
RUN npm ci --omit=dev --ignore-scripts \
    # Fail the build if any production dependency has a known vulnerability.
    # --audit-level=high treats high+critical as build-breaking; moderate and
    # below are informational. Remove --production to audit devDeps too.
    && npm audit --omit=dev --audit-level=high

# ---- Stage 2: minimal runtime ----
# gcr.io/distroless/nodejs22-debian12 contains:
#   - Node.js 22 binary (built against Debian's regularly-patched OpenSSL)
#   - Minimal glibc/libssl from Debian stable (far fewer CVEs than Alpine floating tags)
#   - NO shell, NO apk/apt, NO package manager, NO busybox
# This eliminates the bulk of scanner-reported criticals/highs because the attack
# surface is just Node + the Debian security-team-patched libs it links against.
# :nonroot variant sets USER 65532 (nonroot) by default — no extra USER instruction needed.
FROM gcr.io/distroless/nodejs22-debian12:nonroot

WORKDIR /app

# Copy only the production node_modules and app source from the build stage.
COPY --from=builder /app/node_modules ./node_modules
COPY src/ ./src/

EXPOSE 3000

# distroless does not have 'node' on PATH; reference the binary directly.
CMD ["/nodejs/bin/node", "src/index.js"]
