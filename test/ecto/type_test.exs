defmodule Ecto.TypeTest do
  use ExUnit.Case, async: true

  import Ecto.Type
  alias Ecto.Adapters.{MyXQL, Postgres, Tds}

  @uuid_string "bfe0888c-5c59-4bb3-adfd-71f0b85d3db7"
  @uuid_binary <<191, 224, 136, 140, 92, 89, 75, 179, 173, 253, 113, 240, 184, 93, 61, 183>>
  @mssql_uuid_binary <<140, 136, 224, 191, 89, 92, 179, 75, 173, 253, 113, 240, 184, 93, 61, 183>>

  # We don't effectively dump because we need to keep JSON encoding
  test "dumps through the adapter" do
    assert adapter_dump(MyXQL, {:map, Ecto.UUID}, %{"a" => @uuid_string}) ==
             {:ok, %{"a" => @uuid_string}}

    assert adapter_dump(Postgres, {:map, Ecto.UUID}, %{"a" => @uuid_string}) ==
             {:ok, %{"a" => @uuid_string}}

    assert adapter_dump(Tds, {:map, Elixir.Tds.Ecto.UUID}, %{"a" => @uuid_string}) ==
             {:ok, %{"a" => @uuid_string}}
  end

  # Therefore we need to support both binaries and strings when loading
  test "loads through the adapter" do
    assert adapter_load(MyXQL, {:map, Ecto.UUID}, %{"a" => @uuid_binary}) ==
             {:ok, %{"a" => @uuid_string}}

    assert adapter_load(Postgres, {:map, Ecto.UUID}, %{"a" => @uuid_binary}) ==
             {:ok, %{"a" => @uuid_string}}

    assert adapter_load(Tds, {:map, Elixir.Tds.Ecto.UUID}, %{"a" => @mssql_uuid_binary}) ==
             {:ok, %{"a" => @uuid_string}}

    assert adapter_load(MyXQL, {:map, Ecto.UUID}, %{"a" => @uuid_string}) ==
             {:ok, %{"a" => @uuid_string}}

    assert adapter_load(Postgres, {:map, Ecto.UUID}, %{"a" => @uuid_string}) ==
             {:ok, %{"a" => @uuid_string}}

    assert adapter_load(Tds, {:map, Elixir.Tds.Ecto.UUID}, %{"a" => @uuid_string}) ==
             {:ok, %{"a" => @uuid_string}}
  end

  # A bare nil is declared as varbinary, which date, time, datetime2,
  # datetimeoffset, float and real columns refuse
  @tds_tagged_nil_types [
    date: :date,
    time: :time,
    time_usec: :time,
    naive_datetime: :datetime2,
    naive_datetime_usec: :datetime2,
    utc_datetime: :datetimeoffset,
    utc_datetime_usec: :datetimeoffset,
    float: :float
  ]

  test "tags nil with its TDS type for Tds date, time and float types" do
    for {type, tds_type} <- @tds_tagged_nil_types do
      assert adapter_dump(Tds, type, nil) == {:ok, {nil, tds_type}}
    end
  end

  test "dumps nil as nil for other Tds types" do
    for type <- [:integer, :boolean, :decimal, :string, :binary, :binary_id, :map] do
      assert adapter_dump(Tds, type, nil) == {:ok, nil}
    end
  end

  test "does not tag non-nil Tds values" do
    assert adapter_dump(Tds, :date, ~D[2024-01-01]) == {:ok, ~D[2024-01-01]}
    assert adapter_dump(Tds, :float, 1.5) == {:ok, 1.5}
  end

  test "leaves nil inside a Tds array to the array dumper" do
    assert adapter_dump(Tds, {:array, :date}, [nil]) == {:ok, [nil]}
  end

  defmodule IntDate do
    use Ecto.Type

    def type, do: :date
    def cast(%Date{} = date), do: {:ok, date}
    def load(int), do: {:ok, Date.new!(div(int, 10_000), rem(div(int, 100), 100), rem(int, 100))}
    def dump(%Date{} = date), do: {:ok, date.year * 10_000 + date.month * 100 + date.day}
  end

  # Ecto never calls a custom type's dump/1 for nil, so the adapter cannot know
  # that this type stores its non-nil values as integers.
  test "does not tag nil for a custom Tds type with a :date primitive" do
    assert adapter_dump(Tds, IntDate, ~D[2024-01-01]) == {:ok, 20_240_101}
    assert adapter_dump(Tds, IntDate, nil) == {:ok, nil}
  end
end
