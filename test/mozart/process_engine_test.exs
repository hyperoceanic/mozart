defmodule Mozart.ProcessEngineTest do
  use ExUnit.Case

  alias Mozart.Util
  alias Mozart.UserTaskService, as: UTS
  alias Mozart.ProcessEngine, as: PE
  alias Mozart.ProcessService, as: PS
  alias Mozart.ProcessModelService, as: PMS

  @moduletag timeout: :infinity

  setup do
    {:ok, _pid} = PS.start_link(nil)
    {:ok, _pid} = PMS.start_link(nil)
    {:ok, _pid} = UTS.start_link([])
    %{ok: nil}
  end

  def load_process_models(models) do
    Enum.each(models, fn model -> PMS.load_process_model(model) end)
  end

  test "complex process model" do
    load_process_models(Util.get_complex_process_models())
    model = PMS.get_process_model(:call_process_model)
    data = %{value: 1}

    {:ok, ppid} = PE.start_link(model, data)
    assert PE.get_data(ppid) == %{value: 7}
    assert PE.is_complete(ppid) == true
  end

  test "start server and get id" do
    load_process_models(Util.get_testing_process_models())
    model = PMS.get_process_model(:simple_process_model)
    data = %{foo: "foo"}
    {:ok, ppid} = PE.start_link(model, data)

    assert PE.get_data(ppid) == %{foo: "foo", bar: :bar}
    assert PE.is_complete(ppid) == true
  end

  test "execute process with subprocess" do
    load_process_models(Util.get_testing_process_models())
    model = PMS.get_process_model(:simple_call_process_model)
    data = %{value: 1}
    {:ok, _ppid} = PE.start_link(model, data)
    assert length(Map.keys(PS.get_process_instances())) == 2
  end

  test "execute process with service subprocess" do
    load_process_models(Util.get_testing_process_models())
    model = PMS.get_process_model(:simple_call_service_process_model)
    data = %{value: 1}
    {:ok, ppid} = PE.start_link(model, data)
    assert length(Map.keys(PS.get_process_instances())) == 2
    assert PE.get_data(ppid) == %{value: 1, service: :service}

  end

  test "execute process with choice returning :foo" do
    load_process_models(Util.get_testing_process_models())
    model = PMS.get_process_model(:choice_process_model)
    data = %{value: 1}
    {:ok, ppid} = PE.start_link(model, data)

    assert PE.get_open_tasks(ppid) == []
    assert PE.get_data(ppid) == %{value: 1, foo: :foo}
    assert PE.is_complete(ppid) == true
  end

  test "execute process with choice returning :bar" do
    load_process_models(Util.get_testing_process_models())
    model = PMS.get_process_model(:choice_process_model)
    data = %{value: 11}
    {:ok, ppid} = PE.start_link(model, data)

    assert PE.get_open_tasks(ppid) == []
    assert PE.get_data(ppid) == %{value: 11, bar: :bar}
    assert PE.is_complete(ppid) == true
  end

  test "one user task" do
    load_process_models(Util.get_testing_process_models())
    model = PMS.get_process_model(:user_task_process_model)
    data = %{value: 0}
    {:ok, ppid} = PE.start_link(model, data)

    assert PE.get_data(ppid) == %{value: 0}
    open_tasks = PE.get_open_tasks(ppid)
    assert Enum.map(open_tasks, fn ot -> ot.task_name end) == [:foo]
    assert PE.is_complete(ppid) == false
    assert UTS.get_user_tasks() != []
  end

  test "complete one user task" do
    load_process_models(Util.get_testing_process_models())
    model = PMS.get_process_model(:user_task_process_model)
    data = %{value: 0}
    {:ok, ppid} = PE.start_link(model, data)

    assert PE.get_data(ppid) == %{value: 0}
    open_tasks = PE.get_open_tasks(ppid)
    assert Enum.map(open_tasks, fn ot -> ot.task_name end) == [:foo]

    PE.complete_user_task(ppid, :foo, %{foo: :foo, bar: :bar})
    assert PE.get_data(ppid) == %{value: 0, foo: :foo, bar: :bar}
    assert PE.get_open_tasks(ppid) == []
  end

  test "complete one user task then sevice task" do
    load_process_models(Util.get_testing_process_models())
    model = PMS.get_process_model(:user_task_then_service)
    data = %{value: 0}
    {:ok, ppid} = PE.start_link(model, data)
    assert PE.get_data(ppid) == %{value: 0}
    task_names = Enum.map(PE.get_open_tasks(ppid), fn t -> t.task_name end)
    assert task_names == [:user_task_1]
    PE.complete_user_task(ppid, :user_task_1, %{foo: :foo, bar: :bar})
    assert PE.get_data(ppid) == %{value: 0, foo: :foo, bar: :bar}
    assert PE.get_open_tasks(ppid) == []
  end

  test "complete one servuce task then user task" do
    load_process_models(Util.get_testing_process_models())
    model = PMS.get_process_model(:service_then_user_task)
    data = %{value: 0}
    {:ok, ppid} = PE.start_link(model, data)
    assert PE.get_data(ppid) == %{value: 1}
    task_names = Enum.map(PE.get_open_tasks(ppid), fn t -> t.task_name end)
    assert task_names == [:user_task_1]
    PE.complete_user_task(ppid, :user_task_1, %{foo: :foo, bar: :bar})
    assert PE.get_data(ppid) == %{value: 1, foo: :foo, bar: :bar}
    assert PE.get_open_tasks(ppid) == []
  end

  test "set and get process state model" do
    load_process_models(Util.get_testing_process_models())
    model = PMS.get_process_model(:simple_process_model)
    data = %{foo: :foo}
    {:ok, ppid} = PE.start_link(model, data)
    assert PE.get_model(ppid) == model
  end

  test "set and get data" do
    load_process_models(Util.get_testing_process_models())
    data = %{value: 1}
    model = PMS.get_process_model(:simple_process_model)
    {:ok, ppid} = PE.start_link(model, data)
    PE.set_data(ppid, data)
    assert PE.get_data(ppid) == data
  end

  test "get process model open tasks" do
    load_process_models(Util.get_testing_process_models())
    model = PMS.get_process_model(:simple_process_model)
    data = %{value: 1}
    {:ok, ppid} = PE.start_link(model, data)
    assert PE.get_open_tasks(ppid) == []
    assert PE.is_complete(ppid) == true
  end

  test "complete increment by one task" do
    load_process_models(Util.get_testing_process_models())
    model = PMS.get_process_model(:increment_by_one_process)
    data = %{value: 0}
    {:ok, ppid} = PE.start_link(model, data)
    assert PE.get_data(ppid) == %{value: 1}
    assert PE.get_open_tasks(ppid) == []
    assert PE.is_complete(ppid) == true
  end

  test "two increment tasks in a row" do
    load_process_models(Util.get_testing_process_models())
    model = PMS.get_process_model(:increment_by_one_twice_process)
    data = %{value: 0}
    {:ok, ppid} = PE.start_link(model, data)
    assert PE.get_data(ppid) == %{value: 3}
    assert PE.get_open_tasks(ppid) == []
    assert PE.is_complete(ppid) == true
  end

  test "Three increment tasks in a row" do
    load_process_models(Util.get_testing_process_models())
    model = PMS.get_process_model(:three_increment_by_one_process)
    data = %{value: 0}
    {:ok, ppid} = PE.start_link(model, data)
    assert PE.get_data(ppid) == %{value: 6}
    assert PE.get_open_tasks(ppid) == []
    assert PE.is_complete(ppid) == true
  end
end
