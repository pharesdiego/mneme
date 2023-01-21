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
  defmacro auto_assert({:<-, _, [_, actual]} = expr) do
    assertion = Mneme.Code.mneme_to_exunit(expr)
    __gen_auto_assert__(:replace, __CALLER__, expr, actual, assertion)
  end

  defmacro auto_assert(expr) do
    assertion =
      quote do
        raise ExUnit.AssertionError, message: "No match present"
      end

    __gen_auto_assert__(:new, __CALLER__, expr, expr, assertion)
  end

  @doc false
  def __gen_auto_assert__(type, env, expr, actual, assertion) do
    quote do
      var!(actual) = unquote(actual)
      locals = Keyword.delete(binding(), :actual)
      meta = [module: __MODULE__, binding: locals] ++ unquote(Macro.Env.location(env))

      try do
        unquote(assertion)
      rescue
        error in [ExUnit.AssertionError] ->
          assertion = {unquote(type), unquote(Macro.escape(expr)), var!(actual), meta}

          case Mneme.Server.await_assertion(assertion) do
            {:ok, expr} ->
              expr
              |> Mneme.Code.mneme_to_exunit()
              |> Code.eval_quoted(binding(), __ENV__)

            :error ->
              reraise error, __STACKTRACE__
          end
      end
    end
  end
end
