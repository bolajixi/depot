# depot/Tiltfile
# Local development control plane for the Dola FX platform.
#
# Prerequisites:
#   brew install tilt
#   Fill in odin/.env.local (SMTP_CONNECTION_URI)
#
# Usage:
#   tilt up              # start everything
#   tilt up cassandra    # start a single resource (and its deps)
#   tilt down            # stop everything
#   tilt ci              # run once and exit (CI mode)

# ── Shared Infrastructure ──────────────────────────────────────────────────
# Creates secure_idmsa_network, depot-cassandra, depot-redpanda.
# Must come first — all other stacks join the network as external.
docker_compose('./infra/docker-compose.yml', project_name='depot-infra')

# ── IAM Stack ──────────────────────────────────────────────────────────────
# Traefik, Ory Kratos, Oathkeeper, Hydra, Jaeger
docker_compose(
    '../odin/docker-compose.yml',
    project_name='odin-secure-stack',
    env_file='../odin/.env.local',
)

# ── Distributed Lock Service ───────────────────────────────────────────────
docker_compose('../sync/docker-compose.yml', project_name='sync-stack')

# ── Application Services ───────────────────────────────────────────────────
docker_compose('../fx-backend/docker-compose.yml',                   project_name='dola-backend-stack')
docker_compose('../fx-ledger/docker-compose.yaml',                   project_name='fx-ledger-stack')
docker_compose('../fx-wallet-management-service/docker-compose.yml', project_name='fx-wallet-management-stack')
docker_compose('../fx-order-management-service/docker-compose.yml',  project_name='fx-order-management-stack')
docker_compose('../fx-treasury/docker-compose.yml',                  project_name='fx-treasury-stack')

# ── Startup Ordering ───────────────────────────────────────────────────────
# Tilt will not start a resource until all its deps are healthy.

# IAM internal ordering
resource_deps('kratos-migrate',               ['cassandra'])
resource_deps('kratos_public',                ['kratos-migrate'])
resource_deps('kratos_admin',                 ['kratos-migrate'])
resource_deps('oathkeeper',                   ['kratos_public'])
resource_deps('hydra',                        ['hydra-migrate'])
resource_deps('traefik',                      ['oathkeeper'])

# Sync internal ordering
resource_deps('sync',                         ['etcd'])

# Application service deps
resource_deps('dola-backend',                 ['cassandra', 'oathkeeper'])
resource_deps('fx-ledger',                    ['cassandra'])
resource_deps('fx-wallet-management-service', ['cassandra', 'redpanda', 'fx-ledger', 'sync'])
resource_deps('fx-order-management-service',  ['redpanda', 'fx-wallet-management-service'])
resource_deps('fx-treasury',                  ['cassandra', 'redpanda', 'fx-ledger', 'sync', 'fx-wallet-management-service'])
