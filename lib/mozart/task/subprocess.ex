defmodule Mozart.Task.Subprocess do
  defstruct [
    :name,
    :function,
    :next,
    :uid,
    :sub_process,
    complete: false,
    data: %{},
    completed_sub_tasks: [],
    type: :sub_process
  ]
end
