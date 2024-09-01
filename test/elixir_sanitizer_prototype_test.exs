defmodule ElixirSanitizerPrototypeTest do
  use ExUnit.Case
  doctest ElixirSanitizerPrototype

  test "alerts on injections" do
    assert ElixirSanitizerPrototype.should_alert?("SELECT * from pg_stat_user_tables -- __sanitizer__ ")
  end

  test "doesn't alert on non-injection" do
    assert not ElixirSanitizerPrototype.should_alert?("SELECT * from pg_stat_user_tables")
  end

  test "installs and uninstalls" do
    {:ok, state} = ElixirSanitizerPrototype.init(:ok)
    assert {:reply, :pong, state} == ElixirSanitizerPrototype.handle_call(:ping, nil, state)

    assert {:reply,
            {:all,
             [
               traced: :global,
               match_spec: [],
               meta: false,
               meta_match_spec: false,
               call_memory: false,
               call_time: false,
               call_count: false
             ]}, state} == ElixirSanitizerPrototype.handle_call(:info, nil, state)

    assert true == ElixirSanitizerPrototype.terminate(:normal, state)
  end

  test "triggers on injection" do
    {:ok, conn} =
      Postgrex.start_link(
        hostname: System.get_env("POSTGRES_HOST"),
        username: System.get_env("POSTGRES_USER"),
        password: System.get_env("POSTGRES_PASSWORD"),
        database: System.get_env("POSTGRES_DB"),
        backoff_type: :stop,
        max_restarts: 0
      )
    Process.unlink(conn)

    ElixirSanitizerPrototype.install()

    {:ok, sup} = Task.Supervisor.start_link()

    childe =
      Task.Supervisor.async_nolink(sup, fn ->
        Postgrex.query!(conn, "SELECT * from pg_stat_user_tables -- __sanitizer__ ", [])
        |> dbg()
      end)

    got = Task.yield(childe) || Task.shutdown(childe)

    assert 1 == (:sys.get_state(ElixirSanitizerPrototype)).fire_count

    assert {:exit, :killed} == got
    assert not Process.alive?(conn)

    Supervisor.stop(sup)
    ElixirSanitizerPrototype.uninstall()
  end

  test "doesn't trigger on non-injection" do
    {:ok, conn} =
      Postgrex.start_link(
        hostname: System.get_env("POSTGRES_HOST"),
        username: System.get_env("POSTGRES_USER"),
        password: System.get_env("POSTGRES_PASSWORD"),
        database: System.get_env("POSTGRES_DB"),
        backoff_type: :stop,
        max_restarts: 0
      )
    Process.unlink(conn)

    ElixirSanitizerPrototype.install()

    {:ok, sup} = Task.Supervisor.start_link()

    childe =
      Task.Supervisor.async_nolink(sup, fn ->
        Postgrex.query!(conn, "SELECT * from pg_stat_user_tables", [])
      end)

    got = Task.yield(childe) || Task.shutdown(childe)

    assert 0 == (:sys.get_state(ElixirSanitizerPrototype)).fire_count

    assert {:ok, _} = got
    assert Process.alive?(conn)

    DBConnection.disconnect_all(conn, 500)
    Supervisor.stop(sup)
    ElixirSanitizerPrototype.uninstall()
  end
end
