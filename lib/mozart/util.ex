defmodule Mozart.Util do

  alias Mozart.Data.Task
  alias Mozart.Data.ProcessModel

  def get_simple_model() do
    %ProcessModel{
        name: :foo,
        tasks: [
          %Task{
            name: :foo,
            type: :service,
            function: fn data -> IO.puts(data.foo) end,
            next: nil
          }
        ],
        initial_task: :foo
      }
  end

  def get_increment_by_one_model() do
    %ProcessModel{
        name: :increment_by_one_process,
        tasks: [
          %Task{
            name: :increment_by_one_task,
            type: :service,
            function: fn map -> Map.put(map, :value, map.value + 1) end,
            next: nil
          }
        ],
        initial_task: :increment_by_one_task
      }
  end
end
