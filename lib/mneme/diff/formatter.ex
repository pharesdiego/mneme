defmodule Mneme.Diff.Formatter do
  @moduledoc false

  alias Mneme.Diff
  alias Mneme.Diff.Zipper

  @re_newline ~r/\n|\r\n/

  @doc """
  Highlights the given code based on the instructions.
  """
  @spec highlight_lines(String.t(), [Diff.instruction()]) :: Owl.Data.t()
  def highlight_lines(code, instructions) do
    lines = code |> Owl.Data.lines() |> Enum.reverse()
    [last_line | earlier_lines] = lines
    hl_instructions = denormalize_all(instructions)
    highlighted = highlight(hl_instructions, length(lines), last_line, earlier_lines)

    Enum.map(highlighted, fn
      list when is_list(list) ->
        Enum.filter(list, &(Owl.Data.length(&1) > 0))

      line ->
        line
    end)
  end

  defp highlight(instructions, line_no, current_line, earlier_lines, line_acc \\ [], acc \\ [])

  defp highlight([], _, current_line, earlier_lines, line_acc, acc) do
    Enum.reverse(earlier_lines) ++ [[current_line | line_acc] | acc]
  end

  # no-content highlight
  defp highlight([{_, {{l, c}, {l, c}}} | rest], l, line, earlier, line_acc, acc) do
    highlight(rest, l, line, earlier, line_acc, acc)
  end

  # single-line highlight
  defp highlight([{op, {{l, c}, {l, c2}}} | rest], l, line, earlier, line_acc, acc) do
    {start_line, rest_line} = String.split_at(line, c2 - 1)
    {start_line, token} = String.split_at(start_line, c - 1)
    highlight(rest, l, start_line, earlier, [tag(token, op), rest_line | line_acc], acc)
  end

  # bottom of a multi-line highlight
  defp highlight(
         [{op, {{l, _}, {l2, c2}}} | _] = hl,
         l2,
         line,
         earlier,
         line_acc,
         acc
       )
       when l2 > l do
    {token, rest_line} = String.split_at(line, c2 - 1)
    lines = earlier |> Enum.take(l2 - l - 1) |> Enum.reverse() |> Enum.map(&tag(&1, op))
    [next | rest_earlier] = earlier |> Enum.drop(l2 - l - 1)
    acc = lines ++ [[tag(token, op), rest_line | line_acc] | acc]

    highlight(hl, l, next, rest_earlier, [], acc)
  end

  # top of a multi-line highlight
  defp highlight([{op, {{l, c}, _}} | rest], l, line, earlier, [], acc) do
    {start_line, token} = String.split_at(line, c - 1)
    highlight(rest, l, start_line, earlier, [tag(token, op)], acc)
  end

  defp highlight(instructions, l, line, [next | rest_earlier], line_acc, acc) do
    highlight(instructions, l - 1, next, rest_earlier, [], [[line | line_acc] | acc])
  end

  defp denormalize_all(instructions) do
    instructions
    |> Enum.flat_map(fn
      {op, kind, zipper} ->
        denormalize(kind, op, Zipper.node(zipper), zipper)

      {op, :node, zipper, edit_script} ->
        denormalize_with_edit_script(op, Zipper.node(zipper), edit_script)
    end)
    |> Enum.sort_by(&elem(&1, 1), :desc)
  end

  defp denormalize(:node, op, {:{}, tuple_meta, [left, right]} = node, _) do
    case tuple_meta do
      %{closing: _} ->
        [{op, bounds(node)}]

      _ ->
        {lc1, _} = bounds(left)
        {_, lc2} = bounds(right)
        [{op, {lc1, lc2}}]
    end
  end

  defp denormalize(:node, op, {:var, meta, var}, zipper) do
    var_bounds = bounds({:var, meta, var})
    {{l, c}, {l2, c2}} = var_bounds

    case zipper |> Zipper.up() |> Zipper.node() do
      {:__aliases__, _, _} ->
        case Zipper.right(zipper) do
          nil ->
            [{op, {{l, c - 1}, {l2, c2}}}]

          _ ->
            [{op, {{l, c}, {l2, c2 + 1}}}]
        end

      _ ->
        [{op, var_bounds}]
    end
  end

  defp denormalize(:node, _op, [], _zipper), do: []

  defp denormalize(:node, op, node, _zipper) do
    if bounds = bounds(node) do
      [{op, bounds}]
    else
      []
    end
  end

  defp denormalize(:delimiter, op, {:%, meta, [name, _]}, _) do
    [struct_start, struct_end] = denormalize_delimiter(op, meta, 1, 1)
    {_, {name_end_l, name_end_c}} = bounds(name)

    [
      struct_start,
      {op, {{name_end_l, name_end_c}, {name_end_l, name_end_c + 1}}},
      struct_end
    ]
  end

  defp denormalize(:delimiter, op, {:.., %{line: l, column: c}, [_, _]}, _) do
    [{op, {{l, c}, {l, c + 2}}}]
  end

  defp denormalize(:delimiter, op, {:"..//", %{line: l, column: c}, [_, range_end, _]}, _) do
    {_, {l2, c2}} = bounds(range_end)

    [{op, {{l, c}, {l, c + 2}}}, {op, {{l2, c2}, {l2, c2 + 2}}}]
  end

  defp denormalize(:delimiter, op, {:"[]", meta, _}, _) do
    denormalize_delimiter(op, meta, 1, 1)
  end

  defp denormalize(:delimiter, op, {:{}, meta, _}, _) do
    denormalize_delimiter(op, meta, 1, 1)
  end

  defp denormalize(:delimiter, op, {:%{}, meta, _}, zipper) do
    case zipper |> Zipper.up() |> Zipper.node() do
      {:%, %{line: l, column: c}, _} ->
        [{op, {{l, c}, {l, c + 1}}} | denormalize_delimiter(op, meta, 1, 1)]

      _ ->
        denormalize_delimiter(op, Map.update!(meta, :column, &(&1 - 1)), 2, 1)
    end
  end

  defp denormalize(
         :delimiter,
         op,
         {call, %{line: l, column: c, closing: %{line: l2, column: c2}}, _},
         _
       )
       when is_atom(call) do
    len = Macro.inspect_atom(:remote_call, call) |> String.length()
    [{op, {{l, c}, {l, c + len + 1}}}, {op, {{l2, c2}, {l2, c2 + 1}}}]
  end

  defp denormalize(
         :delimiter,
         op,
         {call, %{line: l, column: c}, _},
         _
       )
       when is_atom(call) do
    len = Macro.inspect_atom(:remote_call, call) |> String.length()
    [{op, {{l, c}, {l, c + len}}}]
  end

  defp denormalize(
         :delimiter,
         op,
         {{:., _, [_left, right]}, %{closing: %{line: l2, column: c2}}, _},
         _
       ) do
    {_, {l, c}} = bounds(right)
    [{op, {{l, c}, {l, c + 1}}}, {op, {{l2, c2}, {l2, c2 + 1}}}]
  end

  defp denormalize(
         :delimiter,
         op,
         {{:., _, [var]}, %{closing: %{line: l2, column: c2}}, _},
         _
       ) do
    {_, {l, c}} = bounds(var)
    [{op, {{l, c}, {l, c + 1}}}, {op, {{l2, c2}, {l2, c2 + 1}}}]
  end

  # Dot call delimiter with no parens, nothing to highlight
  defp denormalize(:delimiter, _op, {{:., _, _}, _, _}, _), do: []

  defp denormalize(:delimiter, op, {atom, %{line: l, column: c}, _}, _) when is_atom(atom) do
    len = Macro.inspect_atom(:remote_call, atom) |> String.length()
    [{op, {{l, c}, {l, c + len}}}]
  end

  # list literals and 2-tuples are structural only in the AST and cannot
  # be highlighted
  defp denormalize(:delimiter, _op, list, _) when is_list(list), do: []
  defp denormalize(:delimiter, _op, {_, _}, _), do: []

  defp denormalize_delimiter(op, meta, start_len, end_len) do
    case meta do
      %{line: l, column: c, closing: %{line: l2, column: c2}} ->
        [{op, {{l, c}, {l, c + start_len}}}, {op, {{l2, c2}, {l2, c2 + end_len}}}]

      _ ->
        []
    end
  end

  defp denormalize_with_edit_script(op, {_, meta, _}, edit_script) do
    %{line: l_start, column: c_start, delimiter: del} = meta

    {l, c} =
      case del do
        ~s(") -> {l_start, c_start + 1}
        ~s(""") -> {l_start + 1, meta.indentation + 1}
      end

    {ops, {l_end, c_end, _}} =
      edit_script
      |> split_edit_script_on_newlines()
      |> Enum.flat_map_reduce({l, c, c}, fn
        {{_, :newline}, _}, {l, _c, c_start} ->
          {[], {l + 1, c_start, c_start}}

        {edit, s}, {l, c, c_start} ->
          c2 =
            if del == ~s(") do
              c + String.length(s) + occurrences(s, ?")
            else
              c + String.length(s)
            end

          op = if edit == :eq, do: op, else: {op, :highlight}
          {[{op, {{l, c}, {l, c2}}}], {l, c2, c_start}}
      end)

    del_start = [{op, {{l_start, c_start}, {l_start, c_start + String.length(del)}}}]
    del_end = [{op, {{l_end, c_end}, {l_end, c_end + String.length(del)}}}]
    del_start ++ ops ++ del_end
  end

  defp split_edit_script_on_newlines(edit_script) do
    edit_script
    |> Stream.flat_map(fn {edit, s} ->
      s
      |> String.split(~r/\n/, include_captures: true)
      |> Enum.map(fn
        "\n" -> {{edit, :newline}, "\n"}
        s -> {edit, s}
      end)
    end)
  end

  defp bounds({:%{}, %{closing: %{line: l2, column: c2}, line: l, column: c}, _}) do
    {{l, c - 1}, {l2, c2 + 1}}
  end

  defp bounds({{:., _, [inner]}, %{closing: %{line: l2, column: c2}}, _}) do
    {start_bound, _} = bounds(inner)
    {start_bound, {l2, c2 + 1}}
  end

  defp bounds({{:., _, _} = call, %{no_parens: true}, []}) do
    bounds(call)
  end

  defp bounds({_, %{closing: %{line: l2, column: c2}, line: l, column: c}, _}) do
    {{l, c}, {l2, c2 + 1}}
  end

  defp bounds({_, %{token: token, line: l, column: c}, _}) do
    {{l, c}, {l, c + String.length(token)}}
  end

  defp bounds({:string, %{line: l, column: c, delimiter: ~s(")}, string}) do
    offset = 2 + String.length(string) + occurrences(string, ?")
    {{l, c}, {l, c + offset}}
  end

  defp bounds({:string, %{line: l, column: c, delimiter: ~s("""), indentation: indent}, string}) do
    n_lines = string |> String.replace_suffix("\n", "") |> String.split(@re_newline) |> length()
    {{l, c}, {l + n_lines + 1, indent + 4}}
  end

  defp bounds({:string, %{line: l, column: c}, string}) do
    {{l, c}, {l, c + String.length(string) - 1}}
  end

  defp bounds({:charlist, %{line: l, column: c, delimiter: "'"}, string}) do
    offset = 2 + String.length(string) + occurrences(string, ?')
    {{l, c}, {l, c + offset}}
  end

  defp bounds({:atom, %{format: :keyword, line: l, column: c}, atom}) do
    atom_bounds(:key, atom, l, c)
  end

  defp bounds({:atom, %{line: l, column: c}, atom}) do
    atom_bounds(:literal, atom, l, c)
  end

  defp bounds({:var, %{line: l, column: c}, atom}) do
    {{l, c}, {l, c + String.length(to_string(atom))}}
  end

  defp bounds({:__aliases__, %{line: l, column: c, last: %{line: l2, column: c2}}, vars}) do
    {:var, _, last_var} = List.last(vars)
    len = last_var |> to_string() |> String.length()
    {{l, c}, {l2, c2 + len}}
  end

  defp bounds({:^, %{line: l, column: c}, [var]}) do
    {_, end_bound} = var |> bounds()
    {{l, c}, end_bound}
  end

  # The . will be between the left and right nodes
  defp bounds({:., _, [left, right]}) do
    {start_bound, _} = bounds(left)
    {_, end_bound} = bounds(right)
    {start_bound, end_bound}
  end

  # The . will be after the single node
  defp bounds({:., _, [inner]}) do
    {start_bound, {l2, c2}} = bounds(inner)
    {start_bound, {l2, c2 + 1}}
  end

  # TODO: handle multi-line using """/''' delimiters
  defp bounds({:"~", %{line: l, column: c, delimiter: del}, [_sigil, [string], modifiers]}) do
    {_, {l2, c2}} = bounds(string)
    del_length = String.length(del) * 2
    {{l, c}, {l2, c2 + del_length + length(modifiers)}}
  end

  defp bounds({:"~", _, _} = sigil) do
    raise ArgumentError, "bounds unimplemented for: #{inspect(sigil)}"
  end

  defp bounds({:__block__, _, []}), do: nil
  defp bounds({:__block__, _, args}), do: bounds(args)

  defp bounds({call, %{line: l, column: c}, args}) when is_atom(call) and is_list(args) do
    [first | _] = args
    last = List.last(args)
    {start_bound, end_bound} = bounds({first, last})
    {min(start_bound, {l, c}), end_bound}
  end

  defp bounds({left, right}) do
    {start_bound, _} = bounds(left)
    {_, end_bound} = bounds(right)

    {start_bound, end_bound}
  end

  defp bounds([node]), do: bounds(node)

  defp bounds(list) when is_list(list) do
    {start_bound, _} = bounds(List.first(list))
    {_, end_bound} = bounds(List.last(list))

    {start_bound, end_bound}
  end

  defp bounds(unimplemented) do
    raise ArgumentError, "bounds unimplemented for: #{inspect(unimplemented)}"
  end

  defp atom_bounds(type, atom, l, c) when type in [:literal, :key, :remote_call] do
    len = Macro.inspect_atom(type, atom) |> String.length()
    {{l, c}, {l, c + len}}
  end

  defp tag(data, :ins), do: Owl.Data.tag(data, :green)
  defp tag(data, :del), do: Owl.Data.tag(data, :red)

  defp tag(data, {:ins, :highlight}), do: Owl.Data.tag(data, [:bright, :green, :underline])
  defp tag(data, {:del, :highlight}), do: Owl.Data.tag(data, [:bright, :red, :underline])

  defp occurrences(string, char, acc \\ 0)
  defp occurrences(<<char, rest::binary>>, char, acc), do: occurrences(rest, char, acc + 1)
  defp occurrences(<<_, rest::binary>>, char, acc), do: occurrences(rest, char, acc)
  defp occurrences(<<>>, _char, acc), do: acc
end
