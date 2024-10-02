defmodule LobbyPlayer do
  defstruct [
    nickname: nil,
    id: "",
    ready: false
  ]
  use Accessible
end

defmodule Lobby do
  defstruct [
    # params
    ruleset: nil,
    ruleset_json: nil,
    session_id: nil,
    # pids
    supervisor: nil,
    exit_monitor: nil,

    # control variables
    error: nil,

    # state
    seats: Map.new([:east, :south, :west, :north], fn seat -> {seat, nil} end),
    players: %{},
    shuffle: false,
    starting: false,
    started: false,
    mods: %{}
  ]
  use Accessible
end


defmodule RiichiAdvanced.LobbyState do
  use GenServer

  def start_link(init_data) do
    IO.puts("Supervisor PID is #{inspect(self())}")
    GenServer.start_link(
      __MODULE__,
      %Lobby{
        session_id: Keyword.get(init_data, :session_id),
        ruleset: Keyword.get(init_data, :ruleset)
      },
      name: Keyword.get(init_data, :name))
  end

  def init(state) do
    IO.puts("Game state PID is #{inspect(self())}")

    # lookup pids of the other processes we'll be using
    [{supervisor, _}] = Registry.lookup(:game_registry, Utils.to_registry_name("lobby", state.ruleset, state.session_id))
    [{exit_monitor, _}] = Registry.lookup(:game_registry, Utils.to_registry_name("exit_monitor_lobby", state.ruleset, state.session_id))

    # read in the ruleset
    ruleset_json = case File.read(Application.app_dir(:riichi_advanced, "/priv/static/rulesets/#{state.ruleset <> ".json"}")) do
      {:ok, ruleset_json} -> ruleset_json
      {:error, _err}      -> nil
    end

    # parse the ruleset now, in order to get the list of eligible mods
    {state, rules} = try do
      case Jason.decode(Regex.replace(~r{//.*|/\*[.\n]*?\*/}, ruleset_json, "")) do
        {:ok, rules} -> {state, rules}
        {:error, err} ->
          state = show_error(state, "WARNING: Failed to read rules file at character position #{err.position}!\nRemember that trailing commas are invalid!")
          {state, %{}}
      end
    rescue
      ArgumentError ->
        state = show_error(state, "WARNING: Ruleset \"#{state.ruleset}\" doesn't exist!")
        {state, %{}}
    end

    default_mods = case RiichiAdvanced.ETSCache.get({state.ruleset, state.session_id}, [], :cache_mods) do
      [mods] -> mods
      []     -> Map.get(rules, "default_mods", [])
    end
    mods = Map.get(rules, "available_mods", [])

    # put params, debouncers, and process ids into state
    state = Map.merge(state, %Lobby{
      ruleset: state.ruleset,
      ruleset_json: ruleset_json,
      session_id: state.session_id,
      error: state.error,
      supervisor: supervisor,
      exit_monitor: exit_monitor,
      mods: mods |> Enum.with_index() |> Map.new(fn {mod, i} -> {mod["id"], %{
        enabled: mod["id"] in default_mods,
        index: i,
        name: mod["name"],
        desc: mod["desc"],
        deps: Map.get(mod, "deps", []),
        conflicts: Map.get(mod, "conflicts", [])
      }} end),
    })

    {:ok, state}
  end

  def put_seat(state, seat, val), do: Map.update!(state, :seats, &Map.put(&1, seat, val))
  def update_seat(state, seat, fun), do: Map.update!(state, :seats, &Map.update!(&1, seat, fun))
  def update_seats(state, fun), do: Map.update!(state, :seats, &Map.new(&1, fn {seat, player} -> {seat, fun.(player)} end))
  def update_seats_by_seat(state, fun), do: Map.update!(state, :seats, &Map.new(&1, fn {seat, player} -> {seat, fun.(seat, player)} end))
  
  def show_error(state, message) do
    state = Map.update!(state, :error, fn err -> if err == nil do message else err <> "\n\n" <> message end end)
    state = broadcast_state_change(state)
    state
  end

  def broadcast_state_change(state) do
    # IO.puts("broadcast_state_change called")
    RiichiAdvancedWeb.Endpoint.broadcast(state.ruleset <> "-lobby:" <> state.session_id, "state_updated", %{"state" => state})
    state
  end

  def handle_call({:new_player, socket}, _from, state) do
    GenServer.call(state.exit_monitor, {:new_player, socket.root_pid, socket.id})
    nickname = if socket.assigns.nickname != "" do socket.assigns.nickname else "player" <> String.slice(socket.id, 10, 4) end
    state = put_in(state.players[socket.id], %LobbyPlayer{nickname: nickname, id: socket.id})
    IO.puts("Player #{socket.id} joined")
    state = broadcast_state_change(state)
    {:reply, [state], state}
  end

  def handle_call({:delete_player, socket_id}, _from, state) do
    state = update_seats(state, fn player -> if player == nil || player.id == socket_id do nil else player end end)
    {_, state} = pop_in(state.players[socket_id])
    IO.puts("Player #{socket_id} exited")
    state = if Enum.empty?(state.players) do
      # all players have left, shutdown
      IO.puts("Stopping lobby #{state.session_id}")
      DynamicSupervisor.terminate_child(RiichiAdvanced.LobbySessionSupervisor, state.supervisor)
      state
    else
      state = broadcast_state_change(state)
      state
    end
    {:reply, :ok, state}
  end

  def handle_cast({:sit, socket_id, seat}, state) do
    seat = case seat do
      "south" -> :south
      "west"  -> :west
      "north" -> :north
      _       -> :east
    end
    state = if state.seats[seat] == nil do
      state = update_seats(state, fn player -> if player == nil || player.id == socket_id do nil else player end end)
      # state = put_in(state.seats[seat], state.players[socket_id])
      state = put_seat(state, seat, state.players[socket_id])
      IO.puts("Player #{socket_id} sat in seat #{seat}")
      state
    else state end
    state = broadcast_state_change(state)
    {:noreply, state}
  end

  def handle_cast({:toggle_shuffle_seats, enabled}, state) do
    state = Map.put(state, :shuffle, enabled)
    state = broadcast_state_change(state)
    {:noreply, state}
  end

  def handle_cast({:toggle_mod, mod, enabled}, state) do
    state = put_in(state.mods[mod].enabled, enabled)
    state = if enabled do
      # enable dependencies and disable conflicting mods
      state = for dep <- state.mods[mod].deps, reduce: state do
        state -> put_in(state.mods[dep].enabled, true)
      end
      for conflict <- state.mods[mod].conflicts, reduce: state do
        state -> put_in(state.mods[conflict].enabled, false)
      end
    else
      # disable dependent mods
      for {dep, opts} <- state.mods, mod in opts.deps, reduce: state do
        state -> put_in(state.mods[dep].enabled, false)
      end
    end
    state = broadcast_state_change(state)
    {:noreply, state}
  end

  def handle_cast({:get_up, socket_id}, state) do
    state = update_seats(state, fn player -> if player == nil || player.id == socket_id do nil else player end end)
    state = broadcast_state_change(state)
    {:noreply, state}
  end

  def handle_cast(:start_game, state) do
    state = Map.put(state, :starting, true)
    state = broadcast_state_change(state)
    mods = Map.get(state, :mods, %{})
    |> Enum.filter(fn {_mod, opts} -> opts.enabled end)
    |> Enum.sort_by(fn {_mod, opts} -> opts.index end)
    |> Enum.map(fn {mod, _opts} -> mod end)
    game_spec = {RiichiAdvanced.GameSupervisor, session_id: state.session_id, ruleset: state.ruleset, mods: mods, name: {:via, Registry, {:game_registry, Utils.to_registry_name("game", state.ruleset, state.session_id)}}}
    state = case DynamicSupervisor.start_child(RiichiAdvanced.GameSessionSupervisor, game_spec) do
      {:ok, _pid} ->
        IO.puts("Starting game session #{state.session_id}")
        # shuffle seats
        state = if state.shuffle do
          Map.update!(state, :seats, fn seats -> Map.keys(seats) |> Enum.zip(Map.values(seats) |> Enum.shuffle()) |> Map.new() end)
        else state end
        IO.inspect(state.seats)
        state = Map.put(state, :started, true)
        state
      {:error, {:shutdown, error}} ->
        IO.puts("Error when starting game session #{state.session_id}")
        IO.inspect(error)
        state = Map.put(state, :starting, false)
        state
      {:error, {:already_started, _pid}} ->
        IO.puts("Already started game session #{state.session_id}")
        state = show_error(state, "A game session for this variant with this same room ID is already in play -- please leave the lobby and try entering it directly!")
        state = Map.put(state, :starting, false)
        state
    end
    state = broadcast_state_change(state)
    {:noreply, state}
  end

end
