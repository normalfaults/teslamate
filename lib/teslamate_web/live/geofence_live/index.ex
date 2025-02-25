defmodule TeslaMateWeb.GeoFenceLive.Index do
  use Phoenix.LiveView

  alias TeslaMate.{Locations, Settings}
  alias TeslaMateWeb.GeoFenceView

  def render(assigns), do: GeoFenceView.render("index.html", assigns)

  def mount(_session, socket) do
    unit_of_length =
      case Settings.get_settings!() do
        %Settings.Settings{unit_of_length: :km} -> :m
        %Settings.Settings{unit_of_length: :mi} -> :ft
      end

    assigns = %{
      geofences: Locations.list_geofences(),
      unit_of_length: unit_of_length,
      flagged: nil
    }

    {:ok, assign(socket, assigns)}
  end

  def handle_event("flag", id, socket) do
    {:noreply, assign(socket, flagged: id)}
  end

  def handle_event("cancel", id, %{assigns: %{flagged: id}} = socket) do
    {:noreply, assign(socket, flagged: nil)}
  end

  def handle_event("delete", id, socket) do
    geofence = Locations.get_geofence!(id)
    {:ok, geofence} = Locations.delete_geofence(geofence)
    geofences = Enum.reject(socket.assigns.geofences, &(&1.id == geofence.id))

    {:noreply, assign(socket, geofences: geofences, flagged: nil)}
  end
end
