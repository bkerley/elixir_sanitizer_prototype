defmodule ElixirSanitizerPrototype do
  require Logger
  use GenServer

  @type state :: %__MODULE__{session: :trace.session()}
  defstruct session: nil

  # API

  def install() do
    GenServer.start(__MODULE__, :ok)
  end

  def uninstall() do
    GenServer.stop(__MODULE__)
  end

  def info() do
    GenServer.call(__MODULE__, :info)
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
    maybe_alert(stmt, caller, conn)
    {:noreply, state}
  end

  defp maybe_alert(stmt, caller, conn) do
    stmt_bin = IO.iodata_to_binary(stmt)

    cond do
      not String.valid?(stmt_bin) ->
        # weird but ok
        :ok

      String.contains?(stmt_bin, sanitizer_slug()) ->
        Logger.emergency(
          found_injection: stmt_bin,
          caller: caller,
          conn: conn
        )

        Process.exit(conn, :kill)
        Process.exit(caller, :kill)
        :injected

      true ->
        :ok
    end
  end
end
