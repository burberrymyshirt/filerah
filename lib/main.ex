defmodule Filerah.Main do
  def start(_type, _args) do
    children = [
      {Filerah.FileWatcher,
       [
         dirs: [
           {"/home/larse/.config", [:recursive]}
         ]
       ]}
    ]

    opts = [strategy: :one_for_one, name: Filerah.Supervisor]

    {:ok, pid} = Supervisor.start_link(children, opts)

    {:ok, pid}
  end
end
