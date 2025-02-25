defmodule TeslaMate.Mapping.UpdatePositionsTest do
  use TeslaMate.DataCase

  alias TeslaMate.Log.{Car, Position}
  alias TeslaMate.{Log, Mapping}

  defp start_mapping(name, responses) do
    srtm_name = :"srtm_#{name}"

    {:ok, _pid} = start_supervised({SRTMMock, name: srtm_name, pid: self(), responses: responses})

    {:ok, _} =
      start_supervised({Mapping, name: name, timeout: 100, deps_srtm: {SRTMMock, srtm_name}})

    :ok
  end

  test "return the elevation", %{test: name} do
    assert %Car{id: car_id} = car_fixture()

    positions =
      %{date: DateTime.utc_now(), latitude: 0, longitude: 0}
      |> List.duplicate(201)
      |> List.replace_at(50, %{date: DateTime.utc_now(), latitude: 1, longitude: 1})
      |> List.replace_at(150, %{date: DateTime.utc_now(), latitude: 1, longitude: 1})
      |> Enum.map(fn position ->
        {:ok, pos} = Log.insert_position(car_id, position)
        pos
      end)

    :ok =
      start_mapping(name, %{
        {0.0, 0.0} => fn -> {:ok, 42} end,
        {1.0, 1.0} => fn ->
          :timer.sleep(100)
          {:ok, 420}
        end
      })

    # blocked
    assert Mapping.get_elevation(name, {0, 0}) == nil
    assert Mapping.get_elevation(name, {0, 0}) == nil
    assert Mapping.get_elevation(name, {0, 0}) == nil

    for {_, i} <- Enum.with_index(positions) do
      if i in [50, 150] do
        assert_receive {SRTM, {:get_elevation, %SRTM.Client{}, 1.0, 1.0}}
      else
        assert_receive {SRTM, {:get_elevation, %SRTM.Client{}, 0.0, 0.0}}
      end
    end

    for {position, i} <- Enum.with_index(positions) do
      if i in [50, 150] do
        assert %Position{elevation: 420.0} = TeslaMate.Repo.get(Position, position.id)
      else
        assert %Position{elevation: 42.0} = TeslaMate.Repo.get(Position, position.id)
      end
    end

    refute_receive _
  end

  @tag :capture_log
  test "handles errors during update!", %{test: name} do
    assert %Car{id: car_id} = car_fixture()

    [p0, p1, p2, p3, p4, p5] =
      [
        %{date: DateTime.utc_now(), latitude: 0, longitude: 0},
        %{date: DateTime.utc_now(), latitude: 1, longitude: 1},
        %{date: DateTime.utc_now(), latitude: 42, longitude: 42},
        %{date: DateTime.utc_now(), latitude: 42, longitude: 42},
        %{date: DateTime.utc_now(), latitude: 42, longitude: 42},
        %{date: DateTime.utc_now(), latitude: 0, longitude: 0}
      ]
      |> Enum.map(fn position ->
        {:ok, pos} = Log.insert_position(car_id, position)
        pos
      end)

    :ok =
      start_mapping(name, %{
        {0.0, 0.0} => fn -> {:ok, 42} end,
        {1.0, 1.0} => fn -> {:error, :boom} end,
        {42.0, 42.0} => fn ->
          :timer.sleep(100)
          {:error, :kaputt}
        end
      })

    assert_receive {SRTM, {:get_elevation, %SRTM.Client{}, 0.0, 0.0}}
    assert_receive {SRTM, {:get_elevation, %SRTM.Client{}, 1.0, 1.0}}
    assert_receive {SRTM, {:get_elevation, %SRTM.Client{}, 42.0, 42.0}}
    assert_receive {SRTM, {:get_elevation, %SRTM.Client{}, 42.0, 42.0}}
    # 4th and 5th are :unavailable

    :timer.sleep(300)

    assert %Position{elevation: 42.0} = TeslaMate.Repo.get(Position, p0.id)
    assert %Position{elevation: nil} = TeslaMate.Repo.get(Position, p1.id)
    assert %Position{elevation: nil} = TeslaMate.Repo.get(Position, p2.id)
    assert %Position{elevation: nil} = TeslaMate.Repo.get(Position, p3.id)
    assert %Position{elevation: nil} = TeslaMate.Repo.get(Position, p4.id)
    assert %Position{elevation: nil} = TeslaMate.Repo.get(Position, p5.id)

    refute_receive _
  end

  test "only fetches positions that are within bounds", %{test: name} do
    assert %Car{id: car_id} = car_fixture()

    [
      %{date: DateTime.utc_now(), latitude: 60.9, longitude: 0},
      %{date: DateTime.utc_now(), latitude: 61, longitude: 0},
      %{date: DateTime.utc_now(), latitude: -55.9, longitude: 0},
      %{date: DateTime.utc_now(), latitude: -56, longitude: 0}
    ]
    |> Enum.map(fn position -> {:ok, _pos} = Log.insert_position(car_id, position) end)

    :ok =
      start_mapping(name, %{
        {-55.9, 0.0} => fn -> {:ok, 42} end,
        {60.9, 0.0} => fn -> {:ok, 42} end
      })

    assert_receive {SRTM, {:get_elevation, %SRTM.Client{}, 60.9, 0.0}}
    assert_receive {SRTM, {:get_elevation, %SRTM.Client{}, -55.9, 0.0}}

    refute_receive _
  end

  defp car_fixture(attrs \\ %{}) do
    {:ok, car} =
      attrs
      |> Enum.into(%{efficiency: 0.153, eid: 42, model: "3", vid: 42, vin: "xxxxx"})
      |> Log.create_car()

    car
  end
end
