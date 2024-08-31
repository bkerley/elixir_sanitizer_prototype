defmodule ElixirSanitizerPrototype do
  require Logger
  use GenServer

  @type state :: %__MODULE__{session: :trace.session(),
                            fire_count: non_neg_integer()}
  defstruct session: nil, fire_count: 0

  # API

  def install() do
    {:ok, _pid} = GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

    :ok
  end

  def uninstall() do
    GenServer.stop(__MODULE__)
  end

  def ping() do
    GenServer.call(__MODULE__, :ping)
  end

  def info() do
    GenServer.call(__MODULE__, :info)
  end

  def state() do
    :sys.get_state(__MODULE__)
  end

  @default_sanitizer_slug "__sanitizer__"
  defp sanitizer_slug() do
    Application.get_env(:elixir_sanitizer_prototype, :sanitizer_slug, @default_sanitizer_slug)
  end

  @mfa_to_trace {DBConnection, :prepare_execute, 4}

  # Callbacks

  @impl GenServer
  def init(:ok) do
    session = :trace.session_create(:elixir_sanitizer_prototype, self(), [])
    :trace.process(session, :all, true, [:call])
    :trace.function(session, @mfa_to_trace, [], [])

    {:ok, %__MODULE__{session: session}}
  end

  @impl GenServer
  def handle_call(:ping, _from, state) do
    {:reply, :pong, state}
  end

  @impl GenServer
  def handle_call(:info, _from, state = %__MODULE__{session: session}) do
    got_info = :trace.info(session, @mfa_to_trace, :all)
    {:reply, got_info, state}
  end

  @impl GenServer
  def terminate(_reason, _state = %__MODULE__{session: session}) do
    :trace.session_destroy(session)
  end

  @impl GenServer
  def handle_info(
        {:trace, caller, :call,
         {DBConnection, :prepare_execute,
          _args = [
            conn,
            %Postgrex.Query{
              statement: stmt
            },
            _params,
            _opts
          ]}},
        state
      ) do
    maybe_alert(state, stmt, caller, conn)
  end

  def should_alert?(stmt) when is_binary(stmt) do
    cond do
      not String.valid?(stmt) ->
        # weird but ok
        false

      String.contains?(stmt, sanitizer_slug()) ->
        true

      true ->
        false
    end
  end

  def should_alert?(stmt) do
    stmt
    |> IO.iodata_to_binary()
    |> should_alert?()
  end

  defp maybe_alert(state, stmt, caller, conn) do
    if should_alert?(stmt) do
      Logger.emergency(
          found_injection: stmt,
          caller: caller,
          caller_live: Process.alive?(caller),
          conn: conn,
          conn_live: Process.alive?(conn)
        )

        Process.exit(conn, :kill)
        Process.exit(caller, :kill)
      {:noreply, %__MODULE__{state | fire_count: state.fire_count + 1}}
    else
      {:noreply, state}
    end
  end
end
