defmodule Reverberation do
  use Crawly.Spider

  # Crawly.Engine.start_spider(Reverberation)
  @spotify_api "https://api.spotify.com/v1/"

  @spotify_user "#{@user_id}"

  @spotify_search_headers [
    {"Accept", "application/json"},
    {"Content-Type", "application/json"},
    {"Authorization", "Bearer #{@token}"}
  ]

  @impl Crawly.Spider
  def base_url(), do: "https://reverberationradio.com"

  @impl Crawly.Spider
  def init() do
    [
      start_urls:
        [
          "https://reverberationradio.com/"
        ] ++
          Enum.map(2..30, fn page_number ->
            "https://reverberationradio.com/page/#{page_number}"
          end)
    ]
  end

  @impl Crawly.Spider
  def parse_item(response) do
    # Parse response body to document
    {:ok, document} = Floki.parse_document(response.body)

    image_map =
      document
      |> Floki.find("div.post")
      |> Floki.find("img")
      |> Stream.filter(fn {_, details, _} -> length(details) == 3 end)
      |> Enum.map(&get_playlist_images(&1))
      |> Map.new()

    posts =
      document
      |> Floki.find("div.post")
      |> Floki.find("p")
      |> Stream.map(fn post ->
        post |> Floki.text() |> String.split("\n")
      end)
      |> Stream.filter(fn post ->
        post |> length() > 2
      end)
      |> Stream.map(&parse_playlist_from_post(&1))
      |> Stream.map(fn playlist ->
        playlist_id = "some_spotify_playlist_id"

        Map.merge(
          playlist,
          %{image: Map.get(image_map, playlist[:title]), playlist_id: playlist_id}
        )
      end)
      |> Enum.each(fn playlist -> playlist |> IO.inspect() end)

    %Crawly.ParsedItem{:items => posts, :requests => []}
  end

  defp get_playlist_images({_, details, _}) do
    [{_, source} | [{_, playlist} | _tail]] = details

    playlist_name =
      playlist
      |> String.split(" - ")
      |> List.last()

    {playlist_name, source}
  end

  defp parse_playlist_from_post([head | tail]) do
    %{
      title: head |> String.trim(),
      tracks:
        tail
        |> Stream.map(fn track ->
          track
          |> String.trim()
          |> String.split([". ", " - "])
        end)
        |> Stream.filter(fn track ->
          track
          |> length() == 3
        end)
        |> Enum.map(fn [_head | [artist | track]] ->
          parsed_artist = artist |> String.trim()
          parsed_track = track |> List.first() |> String.trim()

          {:ok, %HTTPoison.Response{status_code: 200, body: track_response}} =
            "#{@spotify_api}search?q=#{parsed_artist} #{parsed_track}&type=track"
            |> URI.encode()
            |> HTTPoison.get(@spotify_search_headers)

          likely_item =
            track_response
            |> Jason.decode!()
            |> Map.fetch!("tracks")
            |> Map.fetch!("items")
            |> List.first()

          case likely_item do
            nil ->
              %{
                artist: parsed_artist,
                track: parsed_track,
                track_id: nil
              }

            _ ->
              {:ok, track_id} = likely_item |> Map.fetch("id")

              %{
                artist: parsed_artist,
                track: parsed_track,
                track_id: track_id
              }
          end
        end)
    }
  end
end
