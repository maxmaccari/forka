defmodule Forka.Repo do
  use Ecto.Repo,
    otp_app: :forka,
    adapter: Ecto.Adapters.Postgres
end
