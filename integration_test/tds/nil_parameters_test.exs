defmodule Ecto.Integration.NilParametersTest do
  use ExUnit.Case, async: true

  import Ecto.Migrator, only: [up: 4]
  import Ecto.Query, only: [from: 2]
  alias Ecto.Integration.PoolRepo

  defmodule NilParametersMigration do
    use Ecto.Migration

    # :naive_datetime and :utc_datetime create legacy datetime columns, which
    # accept an untyped NULL; the typed datetime2 and datetimeoffset NULLs sent
    # for these fields must be accepted there too.
    def change do
      create table(:nil_parameters_test) do
        add :date_value, :date
        add :time_value, :time
        add :time_usec_value, :time_usec
        add :naive_datetime_value, :naive_datetime
        add :naive_datetime_usec_value, :naive_datetime_usec
        add :utc_datetime_value, :utc_datetime
        add :utc_datetime_usec_value, :utc_datetime_usec
        add :datetimeoffset_value, :datetimeoffset
        add :float_value, :float
        # for IntDate, a custom type with the :date primitive
        add :int_date_value, :integer
      end
    end
  end

  # A custom type with the :date primitive that stores dates as YYYYMMDD
  # integers in an int column.
  defmodule IntDate do
    use Ecto.Type

    def type, do: :date
    def cast(%Date{} = date), do: {:ok, date}
    def load(int), do: {:ok, Date.new!(div(int, 10_000), rem(div(int, 100), 100), rem(int, 100))}
    def dump(%Date{} = date), do: {:ok, date.year * 10_000 + date.month * 100 + date.day}
  end

  defmodule NilParameters do
    use Ecto.Integration.Schema

    schema "nil_parameters_test" do
      field :date_value, :date
      field :time_value, :time
      field :time_usec_value, :time_usec
      field :naive_datetime_value, :naive_datetime
      field :naive_datetime_usec_value, :naive_datetime_usec
      field :utc_datetime_value, :utc_datetime
      field :utc_datetime_usec_value, :utc_datetime_usec
      field :datetimeoffset_value, :utc_datetime_usec
      field :float_value, :float
      field :int_date_value, IntDate
    end
  end

  @values %{
    date_value: ~D[2024-01-01],
    time_value: ~T[09:30:00],
    time_usec_value: ~T[09:30:00.000001],
    naive_datetime_value: ~N[2024-01-01 09:30:00],
    naive_datetime_usec_value: ~N[2024-01-01 09:30:00.000001],
    utc_datetime_value: ~U[2024-01-01 09:30:00Z],
    utc_datetime_usec_value: ~U[2024-01-01 09:30:00.000001Z],
    datetimeoffset_value: ~U[2024-01-01 09:30:00.000001Z],
    float_value: 1.5
  }

  @int_date ~D[2024-01-01]

  @base_migration 3_000_000

  setup_all do
    ExUnit.CaptureLog.capture_log(fn ->
      num = @base_migration + System.unique_integer([:positive])
      up(PoolRepo, num, NilParametersMigration, log: false)
    end)

    :ok
  end

  # SQL Server rejects an untyped (varbinary) NULL for date, time, datetime2,
  # datetimeoffset and float columns, so apart from the two legacy datetime
  # columns these only pass when nil is sent as a typed parameter.
  for field <- Map.keys(@values) do
    test "updates #{field} to nil" do
      row = PoolRepo.insert!(struct(NilParameters, @values))
      changeset = Ecto.Changeset.change(row, [{unquote(field), nil}])

      assert {:ok, _} = PoolRepo.update(changeset)
      assert PoolRepo.get!(NilParameters, row.id) |> Map.fetch!(unquote(field)) == nil
    end

    # Ecto drops a nil change on an already-nil field, so the struct starts
    # with every field set and the changeset clears one.
    test "inserts nil #{field} over a set field" do
      changeset = Ecto.Changeset.change(struct(NilParameters, @values), [{unquote(field), nil}])

      assert {:ok, _} = PoolRepo.insert(changeset)
    end

    test "inserts nil #{field} with insert_all" do
      assert {1, _} = PoolRepo.insert_all(NilParameters, [%{unquote(field) => nil}])
    end

    test "sets #{field} to nil with update_all" do
      row = PoolRepo.insert!(struct(NilParameters, @values))
      query = from(n in NilParameters, where: n.id == ^row.id)

      assert {1, _} = PoolRepo.update_all(query, set: [{unquote(field), nil}])
    end
  end

  test "casts a nil float with type/2" do
    row = PoolRepo.insert!(struct(NilParameters, @values))
    value = nil

    query =
      from(n in NilParameters,
        where: n.id == ^row.id,
        update: [set: [float_value: type(^value, :float)]]
      )

    assert {1, _} = PoolRepo.update_all(query, [])
  end

  # A custom type with a :date primitive is left alone: Ecto never calls its
  # dump/1 for nil, so the adapter cannot know that its non-nil values are
  # stored as integers. Its NULL still reaches the int column untyped, which
  # SQL Server accepts; a NULL declared as date would be refused.
  describe "a custom type with a :date primitive on an integer column" do
    test "updates it to nil" do
      row = PoolRepo.insert!(struct(NilParameters, Map.put(@values, :int_date_value, @int_date)))
      assert PoolRepo.get!(NilParameters, row.id).int_date_value == @int_date

      assert {:ok, _} = PoolRepo.update(Ecto.Changeset.change(row, int_date_value: nil))
      assert PoolRepo.get!(NilParameters, row.id).int_date_value == nil
    end

    test "inserts nil with insert_all" do
      assert {1, _} = PoolRepo.insert_all(NilParameters, [%{int_date_value: nil}])
    end

    test "sets it to nil with update_all" do
      row = PoolRepo.insert!(struct(NilParameters, Map.put(@values, :int_date_value, @int_date)))
      query = from(n in NilParameters, where: n.id == ^row.id)

      assert {1, _} = PoolRepo.update_all(query, set: [int_date_value: nil])
      assert PoolRepo.get!(NilParameters, row.id).int_date_value == nil
    end
  end
end
