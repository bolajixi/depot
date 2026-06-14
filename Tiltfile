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
# dc_resource sets deps so Tilt won't start a resource until its deps are healthy.

# IAM internal ordering
dc_resource('kratos-migrate',               resource_deps=['cassandra'])
dc_resource('kratos_public',                resource_deps=['kratos-migrate'])
dc_resource('kratos_admin',                 resource_deps=['kratos-migrate'])
dc_resource('oathkeeper',                   resource_deps=['kratos_public'])
dc_resource('traefik',                      resource_deps=['oathkeeper'])

# Sync internal ordering
dc_resource('sync',                         resource_deps=['etcd'])

# Application service deps
dc_resource('dola-backend',                 resource_deps=['cassandra', 'oathkeeper'])
dc_resource('fx-ledger',                    resource_deps=['cassandra'])
dc_resource('fx-wallet-management-service', resource_deps=['cassandra', 'redpanda', 'fx-ledger', 'sync'])
dc_resource('fx-order-management-service',  resource_deps=['redpanda', 'fx-wallet-management-service'])
dc_resource('fx-treasury',                  resource_deps=['cassandra', 'redpanda', 'fx-ledger', 'sync', 'fx-wallet-management-service'])
