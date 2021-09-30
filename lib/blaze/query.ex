defmodule Blaze.Query do
  @moduledoc """
  Simplifies the process of constructing a Firestore query, similar to how
  Ecto.Query simplifies queries to its supported databases.

  The simplest way to get started is to `import Blaze.Query`:

  ```elixir
  import Blaze.Query

  query = from("bookCollection", allDescendants: false)
  |> limit(1)
  |> where(author: "Donald Knuth")

  Blaze.API.run_query(conn, parent_path, query)
  ```
  """

  alias GoogleApi.Firestore.V1.Model.{
    CollectionSelector,
    CompositeFilter,
    FieldFilter,
    FieldReference,
    Filter,
    Order,
    StructuredQuery,
    UnaryFilter
  }

  @type t :: StructuredQuery.t

  @doc """
  Constructs a new query object that executes against the given collection.
  """
  @spec from(binary) :: t
  def from(collection), do: from(%StructuredQuery{}, collection, [])

  @doc """
  Updates an existing query to execute against the given collection. If a query
  isn't given, a new query object is created for the given collection and
  options list.
  """
  @spec from(t | binary, binary | Keyword.t) :: t
  def from(%StructuredQuery{}=query, collection), do: from(query, collection, [])
  def from(collection, options), do: from(%StructuredQuery{}, collection, options)

  @doc """
  Updates ane existing query to execute against the given collection with the
  given set of options. Options can be:

  - `allDescendants` - `boolean` - When false, only selects collections that are
  immediate descendants of the parent path specified in the API call.
  """
  @spec from(t, binary, Keyword.t) :: t
  def from(%StructuredQuery{from: f}=query, collection, options) do
    selector = %CollectionSelector{
      collectionId: collection,
      allDescendants: Keyword.get(options, :allDescendants, false),
    }
    case f do
      nil -> %{query | from: [selector]}
      _   -> %{query | from: [selector | f]}
    end
  end

  @doc """
  Creates a filter for the query. If a `where` clause has already been added to
  the query, the filter is either "upgraded" to a composite filter from a field
  or unary filter, or the new conditions are simply added to the existing
  composite filter.

  ## Unary Filters

  It's possible to perform one of two unary filters on a field:

  - Checking for "NaN"
  - Checking for "Null"

  To perform either of these built-in unary filters, you can do the following:

  ```elixir
  # Check for "NaN"
  where(query, grade: :nan)

  # Check for "Null"
  where(query, grade: nil)
  ```

  Any time a key for a given field is either `:nan` or `nil`, a unary filter
  is created. If additional fields and values are given, any unary filters will
  be added to a composite filter along with the remainder of the fields.

  ## Comparison Operators

  By default, if the value for a field is a list then the filter uses the `in`
  operator (e.g. `day_of_week in [1, 2, 3]`). For all other values the filter
  uses `=` as the operator (e.g. `day_of_week = 5`). You can customize the
  operator by passing a tuple for the value in the form of `{op, val}`. For
  example:

  ```elixir
  # Filter for `grade >= 80`
  where(query, grade: {:gte, 80})

  # Filter for `regions contains "us-west"`
  where(query, regions: {:contains, "us-west"})
  ```

  The full list of possible operators:

  - `:eq` - Field equals a value
  - `:lt` - Field less than a value
  - `:lte` - Field less than or equal a value
  - `:gt` - Field is greater than a value
  - `:gte` - Field is greater than or equal to a value
  - `:contains` - Field contains at least one of a set of values
  - `:in` - Field matches at least one of a set of values

  For the `:contains` operator, this only works when the field being filtered
  is an array type. When the value is a list, the `:contains` operator is
  equivalent to "the field has at least one element that matches an element in
  the given value list." When the value is anything else, the `:contains`
  operator is equivalent to "the field has at least one element that matches the
  given value."

  For the `:in` operator, this only works when the field being filtered is
  **not** an array or map type. The value list passed in must be an array of
  values that match the type of the field. E.g. if the field being filtered is
  an integer then the list of possible values must be a list of integers.

  ## Caveats

  **Warning**: Firestore only supports `and` operators for composite filters,
  so calling `where` multiple times will create multiple `and` conditions. For
  example:

  ```elixir
  query
  |> where(author: "Donald Knuth")
  |> where(author: "William Gibson")
  ```

  The above won't work because Firestore can only interpret that as "author is
  Donald Knuth **AND** William Gibson". Calling the `where` function multiple
  times is better suited for composing incremental, compounding filters rather
  than expanding existing filters.
  """
  @spec where(t, Keyword.t | Map.t) :: t
  def where(%StructuredQuery{}=query \\ %StructuredQuery{}, conditions) do
    filter = create_filters(conditions)
    case query.where do
      nil -> %{query | where: filter}
      %CompositeFilter{filters: filters}=comp -> %{query | where: Map.put(comp, :filters, [filter | filters])}
      other -> %{query | where: %CompositeFilter{
        op: "AND",
        filters: [filter, other],
      }}
    end
  end

  @doc """
  Creates one or more filters from a keyword list or map of conditions.
  Conditions may either be field comparisons filters or unary field filters. See
  the module documentation sections for `Comparison Operators` and `Unary
  Filters` for more information.
  """
  @spec create_filters(Keyword.t | Map.t) :: Filter.t
  def create_filters(conditions) when is_list(conditions) or is_map(conditions) do
    case Enum.map(conditions, &create_filter/1) do
      [filter] -> filter
      filters -> %CompositeFilter{
        op: "AND",
        filters: filters,
      }
    end
  end

  @doc """
  Create a single filter for one field. This could result in either a
  `UnaryFilter` or a `FieldFilter` being generated, although everything gets
  wrapped in a `Filter` model anyway for some reason.
  """
  @spec create_filter({binary, term}) :: Filter.t
  def create_filter({field, uop}) when uop in [:nan, nil] do
    %Filter{
      unaryFilter: %UnaryFilter{
        op: field_op(uop, nil),
        field: %FieldReference{fieldPath: field},
      }
    }
  end
  def create_filter({field, {op, value}}) when op in ~w(eq lt lte gt gte contains in)a do
    op |> field_op(value) |> field_filter(field, value)
  end
  def create_filter({field, value}), do: create_filter({field, {:eq, value}})

  @doc """
  Convert a field operator atom to its string representation. Uses the value as
  context to determine both validity and, in the case of `:contains`, which
  specific string representation is needed.
  """
  @spec field_op(atom, term) :: binary
  def field_op(:eq, _), do: "EQUAL"
  def field_op(:lt, _), do: "LESS_THAN"
  def field_op(:lte, _), do: "LESS_THAN_OR_EQUAL"
  def field_op(:gt, _), do: "GREATER_THAN"
  def field_op(:gte, _), do: "GREATER_THAN_OR_EQUAL"
  def field_op(:contains, list) when is_list(list), do: "ARRAY_CONTAINS_ANY"
  def field_op(:contains, _), do: "ARRAY_CONTAINS"
  def field_op(:in, list) when is_list(list), do: "IN"
  def field_op(:in, _), do: raise ArgumentError, "Must pass a list value with the `in` field operator"
  def field_op(:nan, _), do: "IS_NAN"
  def field_op(nil, _), do: "IS_NULL"

  @doc """
  Creates a `Filter` model with the `fieldFilter` attribute set.
  """
  @spec field_filter(binary, binary, term) :: Filter.t
  def field_filter(operator, field, value) when is_binary(operator) and is_binary(field) do
    %Filter{
      fieldFilter: %FieldFilter{
        op: operator,
        field: %FieldReference{fieldPath: field},
        value: Blaze.Document.encode_value(value),
      }
    }
  end

  @spec offset(t, integer) :: t
  def offset(%StructuredQuery{}=query \\ %StructuredQuery{}, num), do: %{query | offset: num}

  @spec limit(t, integer) :: t
  def limit(%StructuredQuery{}=query \\ %StructuredQuery{}, num), do: %{query | limit: num}

  @doc """
  Adds one or more `order by` clauses to the query. If a list is provided, the
  elements may be either field references or a tuple with a field reference and
  an atom representing directionality: `:asc` or `:desc`. If a map is provided,
  every key must be a field reference and every value must be a direction atom.
  """
  @spec order(t, [binary | {binary, atom}] | Map.t) :: t
  def order(%StructuredQuery{}=query \\ %StructuredQuery{}, orders) do
    ordering = create_ordering(orders)
    case query.orderBy do
      nil    -> %{query | orderBy: ordering}
      [prev] -> %{query | orderBy: Enum.concat(ordering, prev)}
    end
  end

  @spec create_ordering([binary | {binary, atom}] | Map.t) :: [Order.t]
  def create_ordering(orders) when is_list(orders) or is_map(orders) do
    Enum.map(orders, &create_order/1)
  end

  @spec create_order(binary | {binary, atom}) :: Order.t
  def create_order({field, dir}) do
    %Order{
      direction: direction(dir),
      field: %FieldReference{fieldPath: field},
    }
  end
  def create_order(field), do: create_order({field, :asc})

  @doc """
  Convert a direction atom to its string representation.
  """
  @spec direction(atom) :: binary
  def direction(:asc), do: "ASCENDING"
  def direction(:desc), do: "DESCENDING"
end
