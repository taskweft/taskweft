import Config

# Supabase Postgres — connection details from environment variables.
# The pooler endpoint (port 6543) is used so edge function deployments
# share the connection pool managed by Supabase PgBouncer.
config :taskweft, Taskweft.Repo,
  url:
    System.get_env("DATABASE_URL") ||
      "ecto://#{System.get_env("SUPABASE_DB_USER", "postgres.hglmgarxgfgtxlmexkfp")}:#{System.get_env("SUPABASE_DB_PASSWORD", "")}@#{System.get_env("SUPABASE_DB_HOST", "aws-0-us-east-1.pooler.supabase.com")}:#{System.get_env("SUPABASE_DB_PORT", "6543")}/#{System.get_env("SUPABASE_DB_NAME", "postgres")}",
  ssl: true,
  pool_size: String.to_integer(System.get_env("POOL_SIZE", "5")),
  socket_options: [:inet6]

config :taskweft, ecto_repos: [Taskweft.Repo]
