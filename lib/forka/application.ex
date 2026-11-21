defmodule Forka.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      ForkaWeb.Telemetry,
      Forka.Repo,
      {DNSCluster, query: Application.get_env(:forka, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Forka.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: Forka.Finch},
      # Forka Games Supervisor
      {DynamicSupervisor, strategy: :one_for_one, name: Forka.GamesSupervisor},
      # Start to serve requests, typically the last entry
      ForkaWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Forka.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ForkaWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
