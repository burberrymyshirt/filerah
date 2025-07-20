defmodule Filerah.FileWatcher do
  use GenServer
  require Logger

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl true
  def init(args) do
    {dirs_opt, fs_args} = Keyword.split(args, [:dirs])

    case Filerah.Dirs.parse_and_collect_directories(dirs_opt) do
      {:ok, all_dirs} ->
        # Pass the collected directories to FileSystem
        updated_args = Keyword.put(fs_args, :dirs, all_dirs)

        case FileSystem.start_link(updated_args) do
          {:ok, watcher_pid} ->
            FileSystem.subscribe(watcher_pid)
            Logger.info("Started watching #{length(all_dirs)} directories")
            {:ok, %{watcher_pid: watcher_pid, watched_dirs: all_dirs}}

          {:error, reason} ->
            Logger.error("Failed to start FileSystem: #{inspect(reason)}")
            {:stop, reason}
        end

      {:error, reason} ->
        Logger.error("Failed to parse directories: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl true
  def handle_info({:file_event, watcher_pid, {path, events}}, %{watcher_pid: watcher_pid} = state) do
    Logger.debug("File event: #{path} - #{inspect(events)}")

    # Handle new directory creation if watching recursively
    if :created in events and File.dir?(path) do
      # Could potentially add new directory to watch list here
      Logger.info("New directory created: #{path}")
    end

    # Your custom event handling logic here

    {:noreply, state}
  end

  @impl true
  def handle_info({:file_event, watcher_pid, :stop}, %{watcher_pid: watcher_pid} = state) do
    Logger.info("File watcher stopped")
    {:noreply, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.warning("Unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(reason, %{watcher_pid: watcher_pid}) do
    Logger.info("FileWatcher terminating: #{inspect(reason)}")

    if Process.alive?(watcher_pid) do
      GenServer.stop(watcher_pid, :shutdown)
    end

    :ok
  end

  def terminate(_reason, _state), do: :ok

  # Public API functions
  def get_watched_directories do
    GenServer.call(__MODULE__, :get_watched_directories)
  end

  @impl true
  def handle_call(:get_watched_directories, _from, %{watched_dirs: dirs} = state) do
    {:reply, dirs, state}
  end
end
