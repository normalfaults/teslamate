defmodule TeslaMate.Api do
  use GenServer

  require Logger

  alias TeslaMate.Auth.{Tokens, Credentials}
  alias TeslaMate.Auth
  alias TeslaMate.Vehicles

  import Core.Dependency, only: [call: 3, call: 2]

  defstruct auth: nil, deps: %{}
  alias __MODULE__, as: State

  @name __MODULE__

  # API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, @name))
  end

  ## State

  def list_vehicles(name \\ @name) do
    GenServer.call(name, :list_vehicles, 35_000)
  end

  def get_vehicle(name \\ @name, id) do
    GenServer.call(name, {:get_vehicle, id}, 35_000)
  end

  def get_vehicle_with_state(name \\ @name, id) do
    GenServer.call(name, {:get_vehicle_with_state, id}, 35_000)
  end

  ## Internals

  def sign_in(name \\ @name, credentials) do
    GenServer.call(name, {:sign_in, credentials})
  end

  def signed_in?(name \\ @name) do
    GenServer.call(name, :signed_in?)
  end

  # Callbacks

  @impl true
  def init(opts) do
    deps = %{
      auth: Keyword.get(opts, :auth, Auth),
      vehicles: Keyword.get(opts, :vehicles, Vehicles),
      tesla_api_auth: Keyword.get(opts, :tesla_api_auth, TeslaApi.Auth),
      tesla_api_vehicle: Keyword.get(opts, :tesla_api_vehicle, TeslaApi.Vehicle)
    }

    case {call(deps.auth, :get_tokens), call(deps.auth, :get_credentials)} do
      {nil, nil} ->
        Logger.info("Please sign in.")
        {:ok, %State{auth: nil, deps: deps}}

      {%Tokens{access: access, refresh: refresh}, _credentials} ->
        api_auth = %TeslaApi.Auth{token: access, refresh_token: refresh}

        case call(deps.tesla_api_auth, :refresh, [api_auth]) do
          {:ok, %TeslaApi.Auth{} = auth} ->
            :ok = call(deps.auth, :save, [auth])

            {:ok, %State{auth: auth, deps: deps}, {:continue, :schedule_refresh}}

          {:error, %TeslaApi.Error{} = error} ->
            Logger.warn(
              "The persisted API tokens could not be refreshed. Please sign in again.\n" <>
                inspect(error)
            )

            {:ok, %State{auth: nil, deps: deps}}
        end

      # TODO remove with v2.0
      {nil, %Credentials{email: email, password: password}} ->
        case call(deps.tesla_api_auth, :login, [email, password]) do
          {:ok, %TeslaApi.Auth{} = auth} ->
            :ok = call(deps.auth, :save, [auth])

            Logger.warn(
              "Signing in with TESLA_USERNAME and TESLA_PASSWORD variables is deprecated. " <>
                "An API token has already been stored in the database. " <>
                "Both variables can be safely removed from the environment. "
            )

            {:ok, %State{auth: auth, deps: deps}, {:continue, :schedule_refresh}}

          {:error, %TeslaApi.Error{} = error} ->
            {:stop, error}
        end
    end
  end

  @impl true
  def handle_call({:sign_in, %Credentials{}}, _from, %State{auth: auth} = state)
      when not is_nil(auth) do
    {:reply, {:error, :already_signed_in}, state}
  end

  def handle_call({:sign_in, %Credentials{email: email, password: password}}, _from, state) do
    case call(state.deps.tesla_api_auth, :login, [email, password]) do
      {:ok, %TeslaApi.Auth{} = auth} ->
        :ok = call(state.deps.auth, :save, [auth])
        :ok = call(state.deps.vehicles, :restart)
        {:reply, :ok, %State{state | auth: auth}, {:continue, :schedule_refresh}}

      {:error, %TeslaApi.Error{error: reason}} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:signed_in?, _from, %State{auth: auth} = state) do
    {:reply, not is_nil(auth), state}
  end

  def handle_call(_command, _from, %State{auth: nil} = state) do
    {:reply, {:error, :not_signed_in}, state}
  end

  def handle_call(:list_vehicles, _from, state) do
    {:reply, do_list_vehicles(state), state}
  end

  def handle_call({:get_vehicle, id}, _from, state) do
    {:reply, do_get_vehicle(id, state), state}
  end

  def handle_call({:get_vehicle_with_state, id}, _from, state) do
    response =
      case call(state.deps.tesla_api_vehicle, :get_with_state, [state.auth, id]) do
        {:error, %TeslaApi.Error{error: reason}} -> {:error, reason}
        {:ok, %TeslaApi.Vehicle{} = vehicle} -> {:ok, vehicle}
      end

    {:reply, response, state}
  end

  @impl true
  def handle_info(:refresh_auth, state) do
    case call(state.deps.tesla_api_auth, :refresh, [state.auth]) do
      {:ok, %TeslaApi.Auth{} = auth} ->
        :ok = call(state.deps.auth, :save, [auth])
        {:noreply, %State{state | auth: auth}, {:continue, :schedule_refresh}}

      {:error, %TeslaApi.Error{error: error, message: reason, env: _}} ->
        {:stop, {error, reason}}
    end
  end

  def handle_info({:ssl_closed, _}, state) do
    {:noreply, state}
  end

  @impl true
  def handle_continue(:schedule_refresh, %State{auth: auth} = state) do
    ms =
      auth.expires_in
      |> Kernel.*(0.8)
      |> round()
      |> :timer.seconds()

    Process.send_after(self(), :refresh_auth, ms)

    {:noreply, state}
  end

  # Private

  defp do_get_vehicle(id, state) do
    with {:ok, vehicles} <- do_list_vehicles(state),
         {:ok, vehicle} <- find_vehicle(vehicles, id) do
      {:ok, vehicle}
    end
  end

  defp do_list_vehicles(%State{auth: auth, deps: deps}) do
    with {:error, %TeslaApi.Error{error: reason}} <- call(deps.tesla_api_vehicle, :list, [auth]) do
      {:error, reason}
    end
  end

  defp find_vehicle(vehicles, id) do
    case Enum.find(vehicles, &match?(%TeslaApi.Vehicle{id: ^id}, &1)) do
      nil -> {:error, :vehicle_not_found}
      vehicle -> {:ok, vehicle}
    end
  end
end
