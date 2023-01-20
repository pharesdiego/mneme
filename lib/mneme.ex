defmodule Mneme do
  @moduledoc """
  Auto assert away.
  """

  @doc """
  Starts Mneme.
  """
  def start do
    children = [Mneme.Server]
    opts = [strategy: :one_for_one, name: Mneme.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @doc """
  Generates a match assertion.
  """
  defmacro auto_assert({:=, _meta, [expected, actual]} = expr) do
    code = __gen_assert_match__(expected)
    __gen_auto_assert__(:replace, __CALLER__, expr, actual, code)
  end

  defmacro auto_assert(expr) do
    code =
      quote do
        raise ExUnit.AssertionError, message: "No match present"
      end

    __gen_auto_assert__(:new, __CALLER__, expr, expr, code)
  end

  @doc false
  def __gen_auto_assert__(type, env, expr, actual, code) do
    quote do
      expr = unquote(Macro.escape(expr))
      var!(actual) = unquote(actual)
      location = unquote(Macro.Env.location(env))

      try do
        unquote(code)
      rescue
        error in [ExUnit.AssertionError] ->
          case Mneme.Server.await_assertion(unquote(type), expr, var!(actual), location) do
            {:ok, expected} ->
              Mneme.__gen_assert_match__(expected)
              |> Code.eval_quoted(binding(), __ENV__)

            :error ->
              reraise error, __STACKTRACE__
          end
      end
    end
  end

  @doc false
  def __gen_assert_match__(expr) do
    quote do
      ExUnit.Assertions.assert(unquote(expr) = var!(actual))
    end
  end
end
