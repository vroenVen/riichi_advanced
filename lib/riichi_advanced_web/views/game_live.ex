defmodule RiichiAdvancedWeb.GameLive do
  use RiichiAdvancedWeb, :live_view

  def mount(params, _session, socket) do

    # TODO check if a game exists,
    # if not, start it
    socket = assign(socket, :session_id, params["id"])
    socket = assign(socket, :session_id, "ac734d3e45036ee0f35315ba668cabfce")
    [{game_state, _}] = Registry.lookup(:game_registry, "game_state-" <> socket.assigns.session_id)
    socket = assign(socket, :game_state, game_state)
    socket = assign(socket, :winner, nil)
    # liveviews mount twice
    if socket.root_pid != nil do
      # TODO use id in pubsub
      Phoenix.PubSub.subscribe(RiichiAdvanced.PubSub, "game:" <> socket.assigns.session_id)
      [turn, players, seat, shimocha, toimen, kamicha, spectator] = GenServer.call(socket.assigns.game_state, {:new_player, socket})

      socket = assign(socket, :loading, false)
      socket = assign(socket, :player_id, socket.id)
      socket = assign(socket, :turn, turn)
      socket = assign(socket, :seat, seat)
      socket = assign(socket, :shimocha, shimocha)
      socket = assign(socket, :toimen, toimen)
      socket = assign(socket, :kamicha, kamicha)
      socket = assign(socket, :spectator, spectator)
      socket = assign(socket, :hands, Map.new(players, fn {seat, player} -> {seat, player.hand} end))
      socket = assign(socket, :ponds, Map.new(players, fn {seat, player} -> {seat, player.pond} end))
      socket = assign(socket, :calls, Map.new(players, fn {seat, player} -> {seat, player.calls} end))
      socket = assign(socket, :draws, Map.new(players, fn {seat, player} -> {seat, player.draw} end))
      socket = assign(socket, :buttons, Map.new(players, fn {seat, player} -> {seat, player.buttons} end))
      socket = assign(socket, :auto_buttons, Map.new(players, fn {seat, player} -> {seat, player.auto_buttons} end))
      socket = assign(socket, :call_buttons, Map.new(players, fn {seat, player} -> {seat, player.call_buttons} end))
      socket = assign(socket, :call_name, Map.new(players, fn {seat, player} -> {seat, player.call_name} end))
      socket = assign(socket, :riichi, Map.new(players, fn {seat, player} -> {seat, "riichi" in player.status} end))
      socket = assign(socket, :big_text, Map.new(players, fn {seat, player} -> {seat, player.big_text} end))
      {:ok, socket}
    else
      empty_bools = %{:east => false, :south => false, :west => false, :north => false}
      empty_lists = %{:east => [], :south => [], :west => [], :north => []}
      empty_maps = %{:east => %{}, :south => %{}, :west => %{}, :north => %{}}
      empty_strs = %{:east => "", :south => "", :west => "", :north => ""}
      socket = assign(socket, :loading, true)
      socket = assign(socket, :seat, :east)
      socket = assign(socket, :turn, :east)
      socket = assign(socket, :shimocha, nil)
      socket = assign(socket, :toimen, nil)
      socket = assign(socket, :kamicha, nil)
      socket = assign(socket, :spectator, false)
      socket = assign(socket, :hands, empty_lists)
      socket = assign(socket, :ponds, empty_lists)
      socket = assign(socket, :calls, empty_lists)
      socket = assign(socket, :draws, empty_lists)
      socket = assign(socket, :buttons, empty_lists)
      socket = assign(socket, :auto_buttons, empty_lists)
      socket = assign(socket, :call_buttons, empty_maps)
      socket = assign(socket, :call_name, empty_strs)
      socket = assign(socket, :riichi, empty_bools)
      socket = assign(socket, :big_text, empty_strs)
      {:ok, socket}
    end
  end

  def render(assigns) do
    ~H"""
    <%= if not @spectator do %>
      <.live_component module={RiichiAdvancedWeb.HandComponent}
        id="hand self"
        game_state={@game_state}
        your_hand?={true}
        your_turn?={@seat == @turn}
        seat={@seat}
        hand={@hands[@seat]}
        draw={@draws[@seat]}
        calls={@calls[@seat]}
        play_tile={&send(self(), {:play_tile, &1, &2})}
        reindex_hand={&send(self(), {:reindex_hand, &1, &2})}
        riichi={@riichi[@seat]}
        />
    <% else %>
      <.live_component module={RiichiAdvancedWeb.HandComponent}
        id="hand self"
        game_state={@game_state}
        your_hand?={false}
        seat={@seat}
        hand={@hands[@seat]}
        draw={@draws[@seat]}
        calls={@calls[@seat]}
        :if={@seat != nil}
        />
    <% end %>
    <.live_component module={RiichiAdvancedWeb.PondComponent} id="pond self" game_state={@game_state} pond={@ponds[@seat]} />
    <.live_component module={RiichiAdvancedWeb.HandComponent}
      id="hand shimocha"
      game_state={@game_state}
      your_hand?={false}
      seat={@shimocha}
      hand={@hands[@shimocha]}
      draw={@draws[@shimocha]}
      calls={@calls[@shimocha]}
      :if={@shimocha != nil}
      />
    <.live_component module={RiichiAdvancedWeb.PondComponent} id="pond shimocha" game_state={@game_state} pond={@ponds[@shimocha]} :if={@shimocha != nil} />
    <.live_component module={RiichiAdvancedWeb.HandComponent}
      id="hand toimen"
      game_state={@game_state}
      your_hand?={false}
      seat={@toimen}
      hand={@hands[@toimen]}
      draw={@draws[@toimen]}
      calls={@calls[@toimen]}
      :if={@toimen != nil}
      />
    <.live_component module={RiichiAdvancedWeb.PondComponent} id="pond toimen" game_state={@game_state} pond={@ponds[@toimen]} :if={@toimen != nil} />
    <.live_component module={RiichiAdvancedWeb.HandComponent}
      id="hand kamicha"
      game_state={@game_state}
      your_hand?={false}
      seat={@kamicha}
      hand={@hands[@kamicha]}
      draw={@draws[@kamicha]}
      calls={@calls[@kamicha]}
      :if={@kamicha != nil}
      />
    <.live_component module={RiichiAdvancedWeb.PondComponent} id="pond kamicha" game_state={@game_state} pond={@ponds[@kamicha]} :if={@kamicha != nil} />
    <.live_component module={RiichiAdvancedWeb.CompassComponent} id="compass" game_state={@game_state} seat={@seat} turn={@turn} riichi={@riichi} />
    <.live_component module={RiichiAdvancedWeb.WinWindowComponent} id="win-window" game_state={@game_state} winner={@winner}/>
    <%= if not @spectator do %>
      <div class="buttons">
        <button class="button" phx-click="button_clicked" phx-value-name={name} :for={name <- @buttons[@seat]}><%= GenServer.call(@game_state, {:get_button_display_name, name}) %></button>
      </div>
      <div class="auto-buttons">
        <%= for {name, checked} <- @auto_buttons[@seat] do %>
          <input id={"auto-button-" <> name} type="checkbox" class="auto-button" phx-click="auto_button_toggled" phx-value-name={name} phx-value-enabled={if checked do "true" else "false" end} checked={checked}>
          <label for={"auto-button-" <> name}><%= GenServer.call(@game_state, {:get_auto_button_display_name, name}) %></label>
        <% end %>
      </div>
      <div class="call-buttons-container">
        <%= for {called_tile, choices} <- @call_buttons[@seat] do %>
          <%= if not Enum.empty?(choices) do %>
            <div class="call-buttons">
              <div class={["tile", called_tile]}></div>
              <div class="call-button-separator"></div>
              <%= for choice <- choices do %>
                <button class="call-button" phx-click="call_button_clicked" phx-value-name={@call_name[@seat]} phx-value-tile={called_tile} phx-value-choice={Enum.join(choice, ",")}>
                <%= for tile <- choice do %>
                  <div class={["tile", tile]}></div>
                <% end %>
                </button>
              <% end %>
            </div>
          <% end %>
        <% end %>
      </div>
    <% end %>
    <div class={["big-text", Utils.get_relative_seat(@seat, seat)]} :for={{seat, text} <- @big_text} :if={text != ""}><%= text %></div>
    <div class={["big-text"]} :if={@loading}>Loading...</div>
    """
  end

  def handle_event("button_clicked", %{"name" => name}, socket) do
    GenServer.cast(socket.assigns.game_state, {:press_button, socket.assigns.seat, name})
    {:noreply, socket}
  end

  def handle_event("auto_button_toggled", %{"name" => name, "enabled" => enabled}, socket) do
    enabled = enabled == "true"
    GenServer.cast(socket.assigns.game_state, {:toggle_auto_button, socket.assigns.seat, name, not enabled})
    {:noreply, socket}
  end

  def handle_event("call_button_clicked", %{"tile" => called_tile, "name" => call_name, "choice" => choice}, socket) do
    call_choice = Enum.map(String.split(choice, ","), &Riichi.to_tile/1)
    GenServer.cast(socket.assigns.game_state, {:run_deferred_actions, %{seat: socket.assigns.seat, call_name: call_name, call_choice: call_choice, called_tile: Riichi.to_tile(called_tile)}})
    {:noreply, socket}
  end

  def handle_info({:play_tile, _tile, index}, socket) do
    if socket.assigns.seat == socket.assigns.turn do
      GenServer.cast(socket.assigns.game_state, {:play_tile, socket.assigns.seat, index})
    end
    {:noreply, socket}
  end
  def handle_info({:reindex_hand, from, to}, socket) do
    GenServer.cast(socket.assigns.game_state, {:reindex_hand, socket.assigns.seat, from, to})
    {:noreply, socket}
  end

  def handle_info(%{topic: topic, event: "state_updated", payload: %{"state" => state}}, socket) do
    if topic == ("game:" <> socket.assigns.session_id) do
      # animate new calls
      num_calls_before = Map.new(socket.assigns.calls, fn {seat, calls} -> {seat, length(calls)} end)
      num_calls_after = Map.new(state.players, fn {seat, player} -> {seat, length(player.calls)} end)
      Enum.each(Map.keys(num_calls_before), fn seat ->
        if num_calls_after[seat] > num_calls_before[seat] do
          relative_seat = Utils.get_relative_seat(socket.assigns.seat, seat)
          send_update(RiichiAdvancedWeb.HandComponent, id: "hand #{relative_seat}", num_new_calls: num_calls_after[seat] - num_calls_before[seat])
        end
      end)

      # animate played tiles
      Enum.each(state.players, fn {seat, player} ->
        if player.last_discard != nil do
          {tile, index} = player.last_discard
          relative_seat = Utils.get_relative_seat(socket.assigns.seat, seat)
          send_update(RiichiAdvancedWeb.HandComponent, id: "hand #{relative_seat}", hand: player.hand ++ player.draw, played_tile: tile, played_tile_index: index)
          send_update(RiichiAdvancedWeb.PondComponent, id: "pond #{relative_seat}", played_tile: tile)
        end
      end)

      socket = assign(socket, :turn, state.turn)
      socket = assign(socket, :winner, state.winner)
      socket = assign(socket, :hands, Map.new(state.players, fn {seat, player} -> {seat, player.hand} end))
      socket = assign(socket, :ponds, Map.new(state.players, fn {seat, player} -> {seat, player.pond} end))
      socket = assign(socket, :calls, Map.new(state.players, fn {seat, player} -> {seat, player.calls} end))
      socket = assign(socket, :draws, Map.new(state.players, fn {seat, player} -> {seat, player.draw} end))
      socket = assign(socket, :buttons, Map.new(state.players, fn {seat, player} -> {seat, player.buttons} end))
      socket = assign(socket, :auto_buttons, Map.new(state.players, fn {seat, player} -> {seat, player.auto_buttons} end))
      socket = assign(socket, :call_buttons, Map.new(state.players, fn {seat, player} -> {seat, player.call_buttons} end))
      socket = assign(socket, :call_name, Map.new(state.players, fn {seat, player} -> {seat, player.call_name} end))
      socket = assign(socket, :riichi, Map.new(state.players, fn {seat, player} -> {seat, "riichi" in player.status} end))
      socket = assign(socket, :big_text, Map.new(state.players, fn {seat, player} -> {seat, player.big_text} end))
      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:reset_anim, hand, seat}, socket) do
    relative_seat = Utils.get_relative_seat(socket.assigns.seat, seat)
    send_update(RiichiAdvancedWeb.HandComponent, id: "hand #{relative_seat}", hand: hand, played_tile: nil, played_tile_index: nil)
    {:noreply, socket}
  end

  def handle_info(data, socket) do
    IO.puts("unhandled handle_info data:")
    IO.inspect(data)
    {:noreply, socket}
  end

end
