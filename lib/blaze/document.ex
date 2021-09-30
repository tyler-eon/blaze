defmodule Blaze.Document do
  @moduledoc """
  An interface to convert to and from `GoogleApi.Firestore.V1.Model.Document`.

  Create proper document structs by passing in primitive Elixir data types. You
  may simply call `encode/1` passing in a Map and a valid `Document` model will
  be returned.

  ## Caveats

  There are some data types that don't natively map between the expected Value
  types and native Elixir types. When _decoding_ these values, whatever raw data
  is returned in the response is returned as-is. When _encoding_ these values,
  developers must wrap them in a tuple with a special key to denote what kind of
  type they should be mapped to. Those types are:

  - `:__firestore_bytes`: Maps the `bytesValue` field.
  - `:__firestore_ref`: Maps the `referenceValue` field.
  - `:__firestore_geo`: Maps the `geoPointValue` field.
  - `:__firestore_time`: Maps the `timestampValue` field.

  If you need to store raw bytes, a reference to another document, a geographic
  point, or a timestamp in a native format recognizable by Firestore then you
  must wrap those values in a tuple with the first element as one of the above
  corresponding keys. For example, to set a timestamp:

  ```elixir
  iex> encode_value({:__firestore_time, time_in_seconds})
  %{timestampValue: %{seconds: time_in_seconds, nanos: 0}}
  ```
  """

  alias GoogleApi.Firestore.V1.Model, as: Model

  @doc """
  Generate a Document model from a map.
  """
  @spec encode(Map.t()) :: Model.Document.t()
  def encode(map) when is_map(map) do
    %Model.Document{
      fields:
        map
        |> Enum.map(&encode_value/1)
        |> Enum.into(%{})
    }
  end

  @doc """
  Encodes a native Elixir term into a Document Value. If a tuple is given, the
  first element is assumed to represent a key. If the key matches a reserved
  key, it applies special encoding rules. If not, it returns a tuple with the
  second element being encoded.

  Read the module documentation (_Caveats_) for more information on the reserved
  keys and what rules are applied to each.
  """
  @spec encode_value({term, term} | term) :: {term, Model.Value.t()} | Model.Value.t()
  def encode_value({:__firestore_bytes, val}), do: %Model.Value{bytesValue: val}
  def encode_value({:__firestore_ref, val}), do: %Model.Value{referenceValue: val}

  def encode_value({:__firestore_geo, {lat, lng}}),
    do: %Model.Value{
      geoPointValue: %{latitude: lat, longitude: lng}
    }

  def encode_value({:__firestore_time, val}),
    do: %Model.Value{
      timestampValue: %{seconds: val, nanos: 0}
    }

  def encode_value({key, val}), do: {key, encode_value(val)}

  def encode_value(val) when is_list(val) do
    %Model.Value{
      arrayValue: %Model.ArrayValue{
        values: Enum.map(val, &encode_value/1)
      }
    }
  end

  def encode_value(val) when is_map(val) do
    %Model.Value{
      mapValue: %Model.MapValue{
        fields: val |> Enum.map(&encode_value/1) |> Enum.into(%{})
      }
    }
  end

  def encode_value(val) when is_boolean(val), do: %Model.Value{booleanValue: val}
  def encode_value(val) when is_float(val), do: %Model.Value{doubleValue: val}
  def encode_value(val) when is_integer(val), do: %Model.Value{integerValue: val}
  def encode_value(val) when is_binary(val), do: %Model.Value{stringValue: val}
  def encode_value(_), do: %Model.Value{nullValue: nil}

  @doc """
  Generate a map from a Document model.
  """
  @spec decode(Model.Document.t()) :: Map.t()
  def decode(%Model.Document{fields: nil}), do: %{}

  def decode(%Model.Document{fields: fields}) do
    fields
    |> Enum.map(&decode_value/1)
    |> Enum.into(%{})
  end

  @doc """
  Decodes a Document Value into a native Elixir term. If a tuple is given, a
  tuple is returned with the second element being decoded.
  """
  @spec decode_value({term, term} | Model.Value.t()) :: {term, term} | term
  def decode_value({key, val}), do: {key, decode_value(val)}
  def decode_value(%Model.Value{arrayValue: %{values: nil}}), do: []

  def decode_value(%Model.Value{arrayValue: %{values: list}}) do
    Enum.map(list, &decode_value/1)
  end

  def decode_value(%Model.Value{mapValue: %{fields: nil}}), do: nil

  def decode_value(%Model.Value{mapValue: %{fields: map}}) do
    map |> Enum.map(&decode_value/1) |> Enum.into(%{})
  end

  def decode_value(%Model.Value{booleanValue: val}) when val != nil, do: val
  def decode_value(%Model.Value{bytesValue: val}) when val != nil, do: val
  def decode_value(%Model.Value{doubleValue: val}) when val != nil, do: val
  def decode_value(%Model.Value{geoPointValue: val}) when val != nil, do: val
  def decode_value(%Model.Value{integerValue: val}) when val != nil, do: val
  def decode_value(%Model.Value{referenceValue: val}) when val != nil, do: val
  def decode_value(%Model.Value{stringValue: val}) when val != nil, do: val
  def decode_value(%Model.Value{timestampValue: val}) when val != nil, do: val
  def decode_value(_), do: nil
end
