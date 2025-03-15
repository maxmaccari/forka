defmodule Forka.Games.GameServer do
  @moduledoc """
  A GenServer implementation for managing game state and operations.

  The GameServer is responsible for:
  - Creating and managing game insstances
  - Handling player actions (joining, leaving, guessing)
  - Managing game lifecycle (starting, restarting, archiving)
  - Maintaining game state throughout play

  Each game has its own dedicated server process identified by a unique ID.
  The server handles all game operations and maintains the state between player interactions.
  """

  use GenServer

  alias Phoenix.PubSub
  alias Forka.Games.Player
  alias Forka.Games.Word
  alias Forka.Games.Game
  alias Forka.Games.Game.GameState

  @pubsub_topic_prefix "game"
  @message_tagger :game_updated

  # Public API

  @doc """
  Starts the GameServer.

  ## Parameters
    - owner: The player who created the game.
    - opts: Options for the game, including:
      - name: The name of the game (default: "Jogo").
      - max_players: The maximum number of players allowed in the game (default: 2).

  ## Returns
    - `{:ok, pid}` if the server is started successfully.
  """
  def start_link(%GameState{} = game_state) do
    GenServer.start_link(__MODULE__, game_state, name: global_name(game_state.id))
  end

  defp global_name(game_id) when is_binary(game_id) do
    {:global, {__MODULE__, game_id}}
  end

  @doc """
  Checks if a game server exists for the given game ID.

  ## Parameters
    - game_id: The ID of the game to check.

  ## Returns
    - `true` if the game server exists.
    - `false` if the game server does not exist.
  """
  def exists?(game_id) when is_binary(game_id) do
    game_id |> whereis() |> is_pid()
  end

  @doc """
  Finds the process ID for a game server with the given game ID.

  ## Parameters
    - game_id: The ID of the game to locate.

  ## Returns
    - The PID of the game server if it exists.
    - `:undefined` if the game server does not exist.
  """
  def whereis(game_id) do
    game_id
    |> global_name()
    |> :global.whereis_name()
  end

  @doc """
  Gets the current game summary.

  ## Parameters
    - game_id: The ID of the game.

  ## Returns
    - The current game summary.
  """
  def get_game(game_id) when is_binary(game_id) do
    GenServer.call(global_name(game_id), :get_game)
  end

  @doc """
  Adds a player to the game.

  Delegates to `Forka.Games.Game.add_player/2`.

  ## Parameters
    - game_id: The ID of the game.
    - player: The player to add.

  ## Returns
    - `{:ok, game_state}` if successful.
    - `{:error, term}` if unsuccessful. See `Forka.Games.Game.add_player/2` for possible error reasons.
  """
  def add_player(game_id, %Player{} = player) when is_binary(game_id) do
    GenServer.call(global_name(game_id), {:add_player, player})
  end

  @doc """
  Removes a player from the game.

  Delegates to `Forka.Games.Game.remove_player/2`.

  ## Parameters
    - game_id: The ID of the game.
    - player_id: The ID of the player to remove.

  ## Returns
    - `{:ok, game_state}` if successful.
    - `{:error, term}` if unsuccessful. See `Forka.Games.Game.remove_player/2` for possible error reasons.
  """
  def remove_player(game_id, player_id) when is_binary(game_id) and is_binary(player_id) do
    GenServer.call(global_name(game_id), {:remove_player, player_id})
  end

  @doc """
  Initializes the game.

  Delegates to `Forka.Games.Game.init_game/1`.

  ## Parameters
    - game_id: The ID of the game.

  ## Returns
    - `{:ok, game_state}` if successful.
    - `{:error, term}` if unsuccessful. See `Forka.Games.Game.init_game/1` for possible error reasons.
  """
  def init_game(game_id) when is_binary(game_id) do
    GenServer.call(global_name(game_id), :init_game)
  end

  @doc """
  Makes a player give up in the game.

  Delegates to `Forka.Games.Game.give_up_player/2`.

  ## Parameters
    - game_id: The ID of the game.
    - player_id: The ID of the player who is giving up.

  ## Returns
    - `{:ok, game_state}` if successful.
    - `{:error, term}` if unsuccessful. See `Forka.Games.Game.give_up_player/2` for possible error reasons.
  """
  def give_up_player(game_id, player_id) when is_binary(game_id) and is_binary(player_id) do
    GenServer.call(global_name(game_id), {:give_up, player_id})
  end

  @doc """
  Makes a guess for the current word in the game.

  Delegates to `Forka.Games.Game.guess/3`.

  ## Parameters
    - game_id: The ID of the game.
    - player_id: The ID of the player making the guess.
    - letter: The letter being guessed.

  ## Returns
    - `{:ok, game_state}` if successful.
    - `{:error, term}` if unsuccessful. See `Forka.Games.Game.guess/3` for possible error reasons.
  """
  def guess(game_id, player_id, letter)
      when is_binary(game_id) and is_binary(letter) and is_binary(player_id) do
    GenServer.call(global_name(game_id), {:guess, letter, player_id})
  end

  @doc """
  Transfers ownership of the game to another player.

  Delegates to `Forka.Games.Game.transfer_ownership_to_player/2`.

  ## Parameters
    - game_id: The ID of the game.
    - player_id: The ID of the player who will become the new owner.

  ## Returns
    - `{:ok, game_state}` if successful.
    - `{:error, term}` if unsuccessful. See `Forka.Games.Game.transfer_ownership_to_player/2` for possible error reasons.
  """
  def transfer_ownership(game_id, player_id) when is_binary(game_id) and is_binary(player_id) do
    GenServer.call(global_name(game_id), {:transfer_ownership, player_id})
  end

  @doc """
  Restarts the game, returning it to the lobby state.

  Delegates to `Forka.Games.Game.restart_game/1`.

  ## Parameters
    - game_id: The ID of the game.

  ## Returns
    - `{:ok, game_state}` if successful.
    - `{:error, term}` if unsuccessful. See `Forka.Games.Game.restart_game/1` for possible error reasons.
  """
  def restart_game(game_id) when is_binary(game_id) do
    GenServer.call(global_name(game_id), :restart_game)
  end

  @doc """
  Archives the game, marking it as completed and no longer active.
  This will stop the server process.

  Delegates to `Forka.Games.Game.archive_game/1`.

  ## Parameters
    - game_id: The ID of the game.

  ## Returns
    - `{:ok, game_state}` if successful.
    - `{:error, term}` if unsuccessful. See `Forka.Games.Game.archive_game/1` for possible error reasons.
  """
  def archive_game(game_id) when is_binary(game_id) do
    GenServer.call(global_name(game_id), :archive_game)
  end

  @doc """
  Subscribes the caller to receive updates for a specific game.

  When events occur in the game (like player actions or state changes),
  subscribers will receive messages in the format `{:game_updated, game_summary}`.

  ## Parameters
    - game_id: The ID of the game to subscribe to.

  ## Returns
    - `:ok` if the subscription is successful.
    - `{:error, term}` if the subscription fails.
  """
  def subscribe(game_id) when is_binary(game_id) do
    PubSub.subscribe(Forka.PubSub, topic(game_id))
  end

  @doc """
  Unsubscribes the caller from receiving updates for a specific game.

  This stops the process from receiving messages about game events.

  ## Parameters
    - game_id: The ID of the game to unsubscribe from.

  ## Returns
    - `:ok` if the unsubscription is successful.
    - `{:error, term}` if the unsubscription fails.
  """
  def unsubscribe(game_id) when is_binary(game_id) do
    PubSub.unsubscribe(Forka.PubSub, topic(game_id))
  end

  # Callbacks
  @impl true
  def init(%GameState{} = game_state) do
    {:ok, game_state}
  end

  @impl true
  def handle_call(:get_game, _from, game) do
    {:reply, Game.to_game_summary(game), game}
  end

  @impl true
  def handle_call({:add_player, player}, _from, game) do
    case Game.add_player(game, player) do
      {:ok, new_game} ->
        broadcast!(new_game)

        {:reply, :ok, new_game}

      {:error, error} ->
        {:reply, {:error, error}, game}
    end
  end

  @impl true
  def handle_call({:remove_player, player_id}, _from, game) do
    case Game.remove_player(game, player_id) do
      {:ok, new_game} ->
        broadcast!(new_game)

        {:reply, :ok, new_game}

      {:error, error} ->
        {:reply, {:error, error}, game}
    end
  end

  @impl true
  def handle_call(:init_game, _from, game) do
    words = [
      # Animals
      Word.new("cachorro", "animal", "O melhor amigo do homem."),
      Word.new("gato", "animal", "Animal doméstico peludo."),
      Word.new("cao", "animal", "Outra palavra para cachorro."),
      Word.new("passaro", "animal", "Animal que voa."),
      Word.new("peixe", "animal", "Animal aquático."),
      # Food
      Word.new("laranja", "comida", "Fruta cítrica popular."),
      Word.new("banana", "comida", "Fruta amarela tropical."),
      Word.new("pizza", "comida", "Prato italiano popular."),
      Word.new("feijao", "comida", "Legume básico brasileiro."),
      Word.new("arroz", "comida", "Alimento básico mundial."),
      # Family
      Word.new("mae", "familia", "Pessoa que nos dá vida."),
      Word.new("pai", "familia", "Chefe da família."),
      Word.new("irmao", "familia", "Parente masculino próximo."),
      Word.new("irma", "familia", "Parente feminina próxima."),
      Word.new("avô", "familia", "Pai do pai ou mãe."),
      # Objects
      Word.new("mesa", "objeto", "Mobília para colocar coisas."),
      Word.new("cadeira", "objeto", "Furniture para sentar."),
      Word.new("livro", "objeto", "Material para leitura."),
      Word.new("caneta", "objeto", "Instrumento para escrever."),
      Word.new("telefone", "objeto", "Dispositivo para comunicação."),
      # Places
      Word.new("casa", "lugar", "Local onde moramos."),
      Word.new("praia", "lugar", "Área junto ao mar."),
      Word.new("parque", "lugar", "Espaço verde público."),
      Word.new("escola", "lugar", "Local de aprendizado."),
      Word.new("hospital", "lugar", "Local de tratamento médico."),
      # Actions
      Word.new("correr", "acao", "Movimentar-se rápido."),
      Word.new("dançar", "acao", "Mover-se ao ritmo da música."),
      Word.new("cantar", "acao", "Produzir sons musicais."),
      Word.new("ler", "acao", "Interpretar texto escrito."),
      Word.new("escrever", "acao", "Registrar por escrito."),
      # Numbers
      Word.new("um", "numero", "Primeiro número natural."),
      Word.new("dois", "numero", "Número seguinte a um."),
      Word.new("tres", "numero", "Número seguinte a dois."),
      Word.new("quatro", "numero", "Número seguinte a três."),
      Word.new("cinco", "numero", "Número seguinte a quatro."),
      # Colors
      Word.new("azul", "cor", "Cor do céu em dia limpo."),
      Word.new("verde", "cor", "Cor da natureza."),
      Word.new("amarelo", "cor", "Cor do sol."),
      Word.new("vermelho", "cor", "Cor do sangue."),
      Word.new("roxo", "cor", "Cor da uva madura."),
      # Weather
      Word.new("sol", "clima", "Astro que ilumina o dia."),
      Word.new("chuva", "clima", "Precipitação atmosférica."),
      Word.new("vento", "clima", "Movimento do ar."),
      Word.new("neve", "clima", "Precipitação gelada."),
      Word.new("nuvem", "clima", "Acúmulo de vapor d'água."),
      # Body Parts
      Word.new("cabeça", "parte_corporal", "Parte superior do corpo."),
      Word.new("olho", "parte_corporal", "Órgão da visão."),
      Word.new("nariz", "parte_corporal", "Órgão do olfato."),
      Word.new("boca", "parte_corporal", "Abertura para alimentação."),
      Word.new("orelha", "parte_corporal", "Órgão da audição."),
      # Transportation
      Word.new("carro", "transporte", "Veículo terrestre motorizado."),
      Word.new("bicicleta", "transporte", "Veículo pedalado."),
      Word.new("onibus", "transporte", "Transporte público coletivo."),
      Word.new("trem", "transporte", "Meio de transporte ferroviário."),
      Word.new("avião", "transporte", "Veículo aéreo.")
    ]

    game_with_words = Game.set_words(game, words |> Enum.shuffle() |> Enum.take(5))

    case game_with_words |> Game.shuffle_players() |> Game.init_game() do
      {:ok, new_game} ->
        broadcast!(new_game)

        {:reply, :ok, new_game}

      {:error, error} ->
        {:reply, {:error, error}, game}
    end
  end

  @impl true
  def handle_call({:give_up, player_id}, _from, game) do
    case Game.give_up_player(game, player_id) do
      {:ok, new_game} ->
        broadcast!(new_game)

        {:reply, :ok, new_game}

      {:error, error} ->
        {:reply, {:error, error}, game}
    end
  end

  @impl true
  def handle_call({:guess, letter, player_id}, _from, game) do
    case Game.guess(game, player_id, letter) do
      {:ok, new_game} ->
        broadcast!(new_game)

        {:reply, {:ok, Game.to_game_summary(new_game)}, new_game}

      {:error, error} ->
        {:reply, {:error, error}, game}
    end
  end

  @impl true
  def handle_call({:transfer_ownership, player_id}, _from, game) do
    case Game.transfer_ownership_to_player(game, player_id) do
      {:ok, new_game} ->
        broadcast!(new_game)

        {:reply, :ok, new_game}

      {:error, error} ->
        {:reply, {:error, error}, game}
    end
  end

  @impl true
  def handle_call(:restart_game, _from, game) do
    case Game.restart_game(game) do
      {:ok, new_game} ->
        broadcast!(new_game)

        {:reply, :ok, new_game}

      {:error, error} ->
        {:reply, {:error, error}, game}
    end
  end

  @impl true
  def handle_call(:archive_game, _from, game) do
    case Game.archive_game(game) do
      {:ok, new_game} ->
        broadcast!(new_game)
        # Return the response and stop the GenServer with normal reason
        {:stop, :normal, :ok, new_game}

      {:error, error} ->
        {:reply, {:error, error}, game}
    end
  end

  # Private Helpers

  defp topic(game_id), do: "#{@pubsub_topic_prefix}:#{game_id}"

  defp broadcast!(%GameState{id: game_id} = game_state) do
    game_summary = Game.to_game_summary(game_state)
    PubSub.broadcast!(Forka.PubSub, topic(game_id), {@message_tagger, game_summary})
  end
end
