defmodule Taskweft.Repo do
  @moduledoc """
  Ecto repository backed by the Supabase Postgres instance
  (project ref: hglmgarxgfgtxlmexkfp).

  Configure via environment variables (see `.env.example`):

      SUPABASE_DB_HOST     aws-0-us-east-1.pooler.supabase.com
      SUPABASE_DB_PORT     6543
      SUPABASE_DB_NAME     postgres
      SUPABASE_DB_USER     postgres.hglmgarxgfgtxlmexkfp
      SUPABASE_DB_PASSWORD <your-project-password>

  For direct (non-pooled) connections use port 5432 and user `postgres`.

  The `ssl: true` option is required by Supabase — the pooler enforces TLS.
  """

  use Ecto.Repo,
    otp_app: :taskweft,
    adapter: Ecto.Adapters.Postgres
end
