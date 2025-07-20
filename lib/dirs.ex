defmodule Filerah.Dirs do
  require Logger
  # Parse directory configuration and collect all directories to watch
  def parse_and_collect_directories(dirs_opt) do
    try do
      parsed_dirs = parse_directory_configs(dirs_opt)
      all_dirs = collect_directories(parsed_dirs)
      {:ok, all_dirs}
    rescue
      error ->
        {:error, {:directory_parsing_failed, error}}
    end
  end

  # Parse the directory configuration into a standardized format
  defp parse_directory_configs(dirs_opt) do
    IO.inspect(dirs_opt)
    Enum.flat_map(dirs_opt, fn
      {:dirs, dir_list} when is_list(dir_list) ->
        Enum.map(dir_list, &parse_single_dir_config/1)

      {:dirs, single_dir} ->
        [parse_single_dir_config(single_dir)]

      {path, config} when is_list(config) ->
        [parse_single_dir_config({path, config})]

      path when is_binary(path) ->
        [parse_single_dir_config(path)]
    end)
  end

  defp parse_single_dir_config({path, config}) when is_list(config) do
    %{
      path: Path.expand(path),
      recursive: Keyword.get(config, :recursive, false),
      max_depth: Keyword.get(config, :max_depth, 32),
      follow_symlinks: Keyword.get(config, :follow_symlinks, false)
    }
  end

  defp parse_single_dir_config(path) when is_binary(path) do
    %{
      path: Path.expand(path),
      recursive: false,
      max_depth: 32,
      follow_symlinks: false
    }
  end

  # Collect all directories based on configuration
  defp collect_directories(parsed_dirs) do
    parsed_dirs
    |> Enum.flat_map(&expand_directory/1)
    |> Enum.uniq()
    |> Enum.filter(&File.dir?/1)
  end

  # Expand a single directory configuration into a list of paths
  defp expand_directory(%{recursive: false, path: path}) do
    if File.dir?(path), do: [path], else: []
  end

  defp expand_directory(%{recursive: true} = config) do
    find_recursive_directories(config.path, config)
  end

  # Improved recursive directory finder using Stream for memory efficiency
  defp find_recursive_directories(root_path, config) do
    if File.dir?(root_path) do
      root_path
      |> stream_directories(config, 0)
      |> Enum.to_list()
    else
      Logger.warning("Directory does not exist: #{root_path}")
      []
    end
  end

  # Stream directories lazily to handle large directory trees efficiently
  defp stream_directories(path, config, current_depth) do
    Stream.resource(
      fn -> {[{path, current_depth}], MapSet.new()} end,
      fn
        {[], _visited} ->
          {:halt, nil}

        {[{current_path, depth} | rest], visited} ->
          cond do
            depth > config.max_depth ->
              {[], {rest, visited}}

            MapSet.member?(visited, current_path) ->
              # Avoid infinite loops from symlinks
              {[], {rest, visited}}

            true ->
              new_visited = MapSet.put(visited, current_path)

              case scan_directory(current_path, config, depth) do
                {:ok, subdirs} ->
                  new_queue = rest ++ Enum.map(subdirs, &{&1, depth + 1})
                  {[current_path], {new_queue, new_visited}}

                {:error, reason} ->
                  Logger.debug("Skipping directory #{current_path}: #{inspect(reason)}")
                  {[], {rest, new_visited}}
              end
          end
      end,
      fn _ -> :ok end
    )
  end

  # Scan a directory and return subdirectories
  defp scan_directory(path, config, _depth) do
    try do
      subdirs =
        path
        |> File.ls!()
        |> Stream.map(&Path.join(path, &1))
        |> Stream.filter(&is_directory?(&1, config.follow_symlinks))
        |> Enum.to_list()

      {:ok, subdirs}
    rescue
      File.Error -> {:error, :permission_denied}
      error -> {:error, error}
    end
  end

  # Check if path is a directory, optionally following symlinks
  defp is_directory?(path, follow_symlinks?) do
    if follow_symlinks? do
      File.dir?(path)
    else
      case File.lstat(path) do
        {:ok, %File.Stat{type: :directory}} -> true
        # Don't follow symlinks
        {:ok, %File.Stat{type: :symlink}} -> false
        _ -> false
      end
    end
  end
end
