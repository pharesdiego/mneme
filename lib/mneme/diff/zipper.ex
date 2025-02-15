# Derived from Sourceror:
# https://github.com/doorgan/sourceror/blob/main/lib/sourceror/zipper.ex
#
# We have to vendor this in in order to teach Zipper about the extended
# AST defined in Mneme.Diff.AST.

defmodule Mneme.Diff.Zipper do
  @moduledoc false

  # Remove once we figure out why these functions cause a "pattern can never
  # match" error:
  #
  # The pattern can never match the type.
  #
  # Pattern: _child = {_, _}
  #
  # Type: nil
  # @dialyzer {:nowarn_function, do_prev: 1, prev_after_remove: 1}

  import Kernel, except: [node: 1]

  @type t :: {tree :: any(), meta :: map()}

  @doc """
  Returns true if the node is a branch.
  """
  def branch?({_, _, args}) when is_list(args), do: true
  def branch?({_, _}), do: true
  def branch?(list) when is_list(list), do: true
  def branch?(_), do: false

  @doc """
  Returns a list of children of the node.
  """
  def children({form, _, args}) when is_atom(form) and is_list(args), do: args
  def children({form, _, args}) when is_list(args), do: [form | args]
  def children({left, right}), do: [left, right]
  def children(list) when is_list(list), do: list
  def children(_), do: []

  @doc """
  Returns a new branch node, given an existing node and new children.
  """
  def make_node({form, meta, _}, args) when is_atom(form), do: {form, meta, args}
  def make_node({{:<<>>, type}, meta, _}, args), do: {{:<<>>, type}, meta, args}
  def make_node({_form, meta, args}, [first | rest]) when is_list(args), do: {first, meta, rest}
  def make_node({_, _}, [left, right]), do: {left, right}
  def make_node({_, _}, args), do: {:{}, [], args}
  def make_node(list, children) when is_list(list), do: children

  @doc """
  Creates a zipper from a tree node.
  """
  def zip(term), do: {term, nil}

  @doc """
  Walks the zipper all the way up and returns the top zipper.
  """
  def top({_, nil} = zipper), do: zipper
  def top(zipper), do: zipper |> up() |> top()

  @doc """
  Returns true if the zipper is at the top.
  """
  def top?({_, nil}), do: true
  def top?(_), do: false

  @doc """
  Walks the zipper all the way up and returns the root node.
  """
  def root(zipper), do: zipper |> top() |> node()

  @doc """
  Returns the node at the zipper.
  """
  def node({tree, _}), do: tree
  def node(nil), do: nil

  @doc """
  Returns the zipper of the leftmost child of the node at this zipper, or
  nil if no there's no children.
  """
  def down({tree, meta}) do
    with true <- branch?(tree),
         [first | rest] <- children(tree) do
      rest = if rest == [], do: nil, else: rest

      {first, %{ptree: {tree, meta}, l: nil, r: rest}}
    else
      _ -> nil
    end
  end

  def down(nil), do: nil

  @doc """
  Returns the zipper of the parent of the node at this zipper, or nil if at the
  top.
  """
  def up({_, nil}), do: nil

  def up({tree, meta}) do
    children = Enum.reverse(meta.l || []) ++ [tree] ++ (meta.r || [])
    {parent, parent_meta} = meta.ptree
    {make_node(parent, children), parent_meta}
  end

  def up(nil), do: nil

  @doc """
  Returns the zipper of the left sibling of the node at this zipper, or nil.
  """
  def left({tree, %{l: [ltree | l], r: r} = meta}),
    do: {ltree, %{meta | l: l, r: [tree | r || []]}}

  def left(_), do: nil

  @doc """
  Returns the leftmost sibling of the node at this zipper, or itself.
  """
  def leftmost({tree, %{l: [_ | _] = l} = meta}) do
    [left | rest] = Enum.reverse(l)
    r = rest ++ [tree] ++ (meta.r || [])
    {left, %{meta | l: nil, r: r}}
  end

  def leftmost(zipper), do: zipper

  @doc """
  Returns the zipper of the right sibling of the node at this zipper, or nil.
  """
  def right({tree, %{r: [rtree | r]} = meta}),
    do: {rtree, %{meta | r: r, l: [tree | meta.l || []]}}

  def right(_), do: nil

  @doc """
  Returns the rightmost sibling of the node at this zipper, or itself.
  """
  def rightmost({tree, %{r: [_ | _] = r} = meta}) do
    [right | rest] = Enum.reverse(r)
    l = rest ++ [tree] ++ (meta.l || [])
    {right, %{meta | l: l, r: nil}}
  end

  def rightmost(zipper), do: zipper

  @doc """
  Replaces the current node in the zipper with a new node.
  """
  def replace({_, meta}, tree), do: {tree, meta}

  @doc """
  Replaces the current node's children in the zipper.
  """
  def replace_children({node, meta}, args), do: {make_node(node, args), meta}

  @doc """
  Replaces the current node in the zipper with the result of applying `fun` to
  the node.
  """
  def update({tree, meta}, fun), do: {fun.(tree), meta}

  @doc """
  Removes the node at the zipper, returning the zipper that would have preceded
  it in a depth-first walk.
  """
  def remove({_, nil}), do: raise(ArgumentError, message: "Cannot remove the top level node.")

  def remove({_, meta}) do
    case meta.l do
      [left | rest] ->
        prev_after_remove({left, %{meta | l: rest}})

      _ ->
        children = meta.r || []
        {parent, parent_meta} = meta.ptree
        {make_node(parent, children), parent_meta}
    end
  end

  defp prev_after_remove(zipper) do
    if child = branch?(node(zipper)) && down(zipper) do
      prev_after_remove(rightmost(child))
    else
      zipper
    end
  end

  @doc """
  Inserts the item as the left sibling of the node at this zipper, without
  moving. Raises an `ArgumentError` when attempting to insert a sibling at the
  top level.
  """
  def insert_left({_, nil}, _),
    do: raise(ArgumentError, message: "Can't insert siblings at the top level.")

  def insert_left({tree, meta}, child) do
    {tree, %{meta | l: [child | meta.l || []]}}
  end

  @doc """
  Inserts the item as the right sibling of the node at this zipper, without
  moving. Raises an `ArgumentError` when attempting to insert a sibling at the
  top level.
  """
  def insert_right({_, nil}, _),
    do: raise(ArgumentError, message: "Can't insert siblings at the top level.")

  def insert_right({tree, meta}, child) do
    {tree, %{meta | r: [child | meta.r || []]}}
  end

  @doc """
  Inserts the item as the leftmost child of the node at this zipper,
  without moving.
  """
  def insert_child({tree, meta}, child) do
    {do_insert_child(tree, child), meta}
  end

  @doc """
  Inserts the item as the rightmost child of the node at this zipper,
  without moving.
  """
  def append_child({tree, meta}, child) do
    {do_append_child(tree, child), meta}
  end

  @doc """
  Returns the following zipper in depth-first pre-order.
  """
  def next({tree, _} = zipper) do
    if branch?(tree) && down(zipper), do: down(zipper), else: skip(zipper)
  end

  def next(nil), do: nil

  @doc """
  Returns the zipper of the right sibling of the node at this zipper, or the
  next zipper when no right sibling is available.

  This allows to skip subtrees while traversing the siblings of a node.

  The optional second parameters specifies the `direction`, defaults to
  `:next`.

  If no right/left sibling is available, this function returns the same value as
  `next/1`/`prev/1`.

  The function `skip/1` behaves like the `:skip` in `traverse_while/2` and
  `traverse_while/3`.
  """
  def skip(zipper, direction \\ :next)
  def skip(zipper, :next), do: right(zipper) || next_up(zipper)
  def skip(zipper, :prev), do: left(zipper) || prev_up(zipper)

  defp next_up(zipper) do
    if parent = up(zipper) do
      right(parent) || next_up(parent)
    end
  end

  defp prev_up(zipper) do
    if parent = up(zipper) do
      left(parent) || prev_up(parent)
    end
  end

  @doc """
  Returns the previous zipper in depth-first pre-order. If it's already at
  the end, it returns nil.
  """
  def prev(zipper) do
    if left = left(zipper) do
      do_prev(left)
    else
      up(zipper)
    end
  end

  defp do_prev(zipper) do
    if child = branch?(node(zipper)) && down(zipper) do
      do_prev(rightmost(child))
    else
      zipper
    end
  end

  @doc """
  Traverses the tree in depth-first pre-order calling the given function for
  each node. When the traversal is finished, the zipper will be back where it began.

  If the zipper is not at the top, just the subtree will be traversed.

  The function must return a zipper.
  """
  def traverse({_tree, nil} = zipper, fun) do
    do_traverse(zipper, fun)
  end

  def traverse({tree, meta}, fun) do
    {updated, _meta} = do_traverse({tree, nil}, fun)
    {updated, meta}
  end

  defp do_traverse(zipper, fun) do
    zipper = fun.(zipper)
    if next = next(zipper), do: do_traverse(next, fun), else: top(zipper)
  end

  @doc """
  Traverses the tree in depth-first pre-order calling the given function for
  each node with an accumulator. When the traversal is finished, the zipper
  will be back where it began.

  If the zipper is not at the top, just the subtree will be traversed.
  """
  def traverse({_tree, nil} = zipper, acc, fun) do
    do_traverse(zipper, acc, fun)
  end

  def traverse({tree, meta}, acc, fun) do
    {{updated, _meta}, acc} = do_traverse({tree, nil}, acc, fun)
    {{updated, meta}, acc}
  end

  defp do_traverse(zipper, acc, fun) do
    {zipper, acc} = fun.(zipper, acc)
    if next = next(zipper), do: do_traverse(next, acc, fun), else: {top(zipper), acc}
  end

  @doc """
  Traverses the tree in depth-first pre-order calling the given function for
  each node.

  The traversing will continue if the function returns `{:cont, zipper}`,
  skipped for `{:skip, zipper}` and halted for `{:halt, zipper}`. When the
  traversal is finished, the zipper will be back where it began.

  If the zipper is not at the top, just the subtree will be traversed.

  The function must return a zipper.
  """
  def traverse_while({_tree, nil} = zipper, fun) do
    do_traverse_while(zipper, fun)
  end

  def traverse_while({tree, meta}, fun) do
    {updated, _meta} = do_traverse({tree, nil}, fun)
    {updated, meta}
  end

  defp do_traverse_while(zipper, fun) do
    case fun.(zipper) do
      {:cont, zipper} ->
        if next = next(zipper), do: do_traverse_while(next, fun), else: top(zipper)

      {:skip, zipper} ->
        if skipped = skip(zipper), do: do_traverse_while(skipped, fun), else: top(zipper)

      {:halt, zipper} ->
        top(zipper)
    end
  end

  @doc """
  Traverses the tree in depth-first pre-order calling the given function for
  each node with an accumulator. When the traversal is finished, the zipper
  will be back where it began.

  The traversing will continue if the function returns `{:cont, zipper, acc}`,
  skipped for `{:skip, zipper, acc}` and halted for `{:halt, zipper, acc}`

  If the zipper is not at the top, just the subtree will be traversed.
  """
  def traverse_while({_tree, nil} = zipper, acc, fun) do
    do_traverse_while(zipper, acc, fun)
  end

  def traverse_while({tree, meta}, acc, fun) do
    {{updated, _meta}, acc} = do_traverse({tree, nil}, acc, fun)
    {{updated, meta}, acc}
  end

  defp do_traverse_while(zipper, acc, fun) do
    case fun.(zipper, acc) do
      {:cont, zipper, acc} ->
        if next = next(zipper), do: do_traverse_while(next, acc, fun), else: {top(zipper), acc}

      {:skip, zipper, acc} ->
        if skip = skip(zipper), do: do_traverse_while(skip, acc, fun), else: {top(zipper), acc}

      {:halt, zipper, acc} ->
        {top(zipper), acc}
    end
  end

  @doc """
  Returns a zipper to the node that satisfies the predicate function, or `nil`
  if none is found.

  The optional second parameters specifies the `direction`, defaults to
  `:next`.
  """
  def find(zipper, direction \\ :next, predicate)

  def find(nil, _direction, _predicate), do: nil

  def find({tree, _} = zipper, direction, predicate)
      when direction in [:next, :prev] and is_function(predicate) do
    if predicate.(tree) do
      zipper
    else
      zipper =
        case direction do
          :next -> next(zipper)
          :prev -> prev(zipper)
        end

      zipper && find(zipper, direction, predicate)
    end
  end

  defp do_insert_child({form, meta, args}, child) when is_list(args) do
    {form, meta, [child | args]}
  end

  defp do_insert_child(list, child) when is_list(list), do: [child | list]
  defp do_insert_child({left, right}, child), do: {:{}, [], [child, left, right]}

  defp do_append_child({form, meta, args}, child) when is_list(args) do
    {form, meta, args ++ [child]}
  end

  defp do_append_child(list, child) when is_list(list), do: list ++ [child]
  defp do_append_child({left, right}, child), do: {:{}, [], [left, right, child]}
end
