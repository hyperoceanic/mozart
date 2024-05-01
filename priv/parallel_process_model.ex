alias Mozart.Data.ProcessModel
alias Mozart.Data.Task

%ProcessModel{
  name: :paralled_process_model,
  tasks: [
    %Task{
      name: :two_flows,
      type: parallel,
      multi_next: [:add_one, :add_three]
    },
    %Task{
      name: :add_one,
      function: fn data -> Map.put(data, :value, data.value + 1) end,
      next: :add_two
    },
    %Task{
      name: :add_two,
      function: fn data -> Map.put(data, :value, data.value + 2) end,
      next: nil
    },
    %Task{
      name: :add_three,
      function: fn data -> Map.put(data, :value, data.value + 1) end,
      next: nil
    }
  ]
}
