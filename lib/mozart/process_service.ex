defmodule Mozart.ProcessService do
  @moduledoc """
  This modeule provides services required by individual `Mozart.ProcessEngine` instances. Currently,
  it has no user level functions. Subject to change.
  """

  @doc false
  use GenServer

  alias Mozart.ProcessEngine, as: PE
  alias Mozart.UserService, as: US

  require Logger

  ## Client API
  @doc false
  def start_link(_init_arg) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  @doc false
  def get_cached_state(uid) do
    GenServer.call(__MODULE__, {:get_cached_state, uid})
  end

  @doc """
  Returns the state of the completed process corresponding to the process engine's uid
  """
  def get_completed_process(uid) do
    GenServer.call(__MODULE__, {:get_completed_process, uid})
  end

  @doc """
  Returns the user tasks that can be completed by users belonging to one of the input groups.
  """
  def get_user_tasks_for_groups(groups) do
    GenServer.call(__MODULE__, {:get_user_tasks_for_groups, groups})
  end

  def insert_completed_process(process_state) do
    GenServer.cast(__MODULE__, {:insert_completed_process, process_state})
  end

  @doc """
  Get a user task by uid
  """
  def get_user_task(uid) do
    GenServer.call(__MODULE__, {:get_user_task, uid})
  end

  @doc false
  def get_completed_processes() do
    GenServer.call(__MODULE__, :get_completed_processes)
  end

  @doc false
  def get_process_ppid(process_uid) do
    GenServer.call(__MODULE__, {:get_process_ppid, process_uid})
  end

  @doc false
  def get_user_tasks() do
    GenServer.call(__MODULE__, :get_user_tasks)
  end

  @doc """
  Get user tasks eligible for assignment and completion by the specified user.
  """
  def get_user_tasks_for_user(user_id) do
    GenServer.call(__MODULE__, {:get_user_tasks_for_user, user_id})
  end

  @doc false
  def register_process_instance(uid, pid) do
    GenServer.cast(__MODULE__, {:register_process_instance, uid, pid})
  end

  @doc false
  def process_completed_process_instance(process_state) do
    GenServer.call(__MODULE__, {:process_completed_process_instance, process_state})
  end

  @doc false
  def get_state() do
    GenServer.call(__MODULE__, :get_state)
  end

  @doc false
  def complete_user_task(ppid, user_task, data) do
    GenServer.cast(__MODULE__, {:complete_user_task, ppid, user_task, data})
  end

  @doc false
  def assign_user_task(task, user_id) do
    GenServer.cast(__MODULE__, {:assign_user_task, task, user_id})
  end

  @doc false
  def insert_user_task(task) do
    GenServer.cast(__MODULE__, {:insert_user_task, task})
  end

  @doc false
  def clear_user_tasks() do
    GenServer.cast(__MODULE__, :clear_user_tasks)
  end

  @doc false
  def clear_state() do
    GenServer.call(__MODULE__, :clear_state)
  end

  @doc false
  def cache_pe_state(uid, pe_state) do
    GenServer.call(__MODULE__, {:cache_pe_state, uid, pe_state})
  end

  @doc """
  Loads a list of `Mozart.Data.ProcessModel`s into the state of the
  ProcessService.
  """
  def load_process_models(models) do
    GenServer.call(__MODULE__, {:load_process_models, models})
  end

  @doc """
  Retrieves a process model by name.
  """
  def get_process_model(model_name) do
    GenServer.call(__MODULE__, {:get_process_model, model_name})
  end

  @doc """
  Loads a single process model in the repository.
  """
  def load_process_model(model) do
    GenServer.call(__MODULE__, {:load_process_model, model})
  end

  @doc false
  def clear_then_load_process_models(models) do
    GenServer.call(__MODULE__, {:clear_then_load_process_models, models})
  end

  @doc """
  Get process model db
  """
  def get_process_model_db() do
    GenServer.call(__MODULE__, :get_process_model_db)
  end

  @doc """
  Get process model db
  """
  def get_completed_process_db() do
    GenServer.call(__MODULE__, :get_completed_process_db)
  end

  @doc """
  Get process model db
  """
  def get_user_task_db() do
    GenServer.call(__MODULE__, :get_user_task_db)
  end

  ## Callbacks

  @doc false
  def init(_init_arg) do
    {:ok, user_task_db} = CubDB.start_link(data_dir: "database/user_task_db")
    {:ok, completed_process_db} = CubDB.start_link(data_dir: "database/completed_process_db")
    {:ok, process_model_db} = CubDB.start_link(data_dir: "database/process_model_db")

    initial_state = %{
      process_instances: %{},
      restart_state_cache: %{},
      user_task_db: user_task_db,
      completed_process_db: completed_process_db,
      process_model_db: process_model_db
    }

    Logger.info("Process service initialized")

    {:ok, initial_state}
  end

  def handle_call(:get_process_model_db, _from, state) do
    {:reply, state.process_model_db, state}
  end

  def handle_call(:get_user_task_db, _from, state) do
    {:reply, state.user_task_db, state}
  end

  def handle_call(:get_completed_process_db, _from, state) do
    {:reply, state.completed_process_db, state}
  end

  @doc false
  def handle_call(:clear_state, _from, state) do
    CubDB.clear(state.user_task_db)
    CubDB.clear(state.completed_process_db)
    CubDB.clear(state.process_model_db)

    new_state = %{
      process_instances: %{},
      restart_state_cache: %{}
    }

    {:reply, :ok, new_state}
  end

  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  def handle_call(:get_completed_processes, _from, state) do
    completed_processes =
      CubDB.select(state.completed_process_db)
      |> Stream.map(fn {_k, v} -> v end)
      |> Enum.to_list()

    {:reply, completed_processes, state}
  end

  def handle_call({:get_process_ppid, process_uid}, _from, state) do
    {:reply, Map.get(state.process_instances, process_uid), state}
  end

  def handle_call({:get_completed_process, uid}, _from, state) do
    {:reply, CubDB.get(state.completed_process_db, uid), state}
  end

  def handle_call({:get_user_tasks_for_groups, groups}, _from, state) do
    tasks = get_user_tasks_for_groups_local(groups, state)
    {:reply, tasks, state}
  end

  def handle_call({:get_user_tasks_for_user, user_id}, _from, state) do
    member_groups = US.get_assigned_groups(user_id)
    tasks = get_user_tasks_for_groups_local(member_groups, state)
    {:reply, tasks, state}
  end

  def handle_call(:get_user_tasks, _from, state) do
    {:reply, get_user_tasks(state), state}
  end

  def handle_call({:get_user_task, uid}, _from, state) do
    {:reply, get_user_task_by_id(state, uid), state}
  end

  def handle_call({:get_cached_state, uid}, _from, state) do
    {pe_state, new_cache} = Map.pop(state.restart_state_cache, uid)
    state = if pe_state, do: Map.put(state, :restart_state_cache, new_cache), else: state
    {:reply, pe_state, state}
  end

  def handle_call({:cache_pe_state, uid, pe_state}, _from, state) do
    state =
      Map.put(state, :restart_state_cache, Map.put(state.restart_state_cache, uid, pe_state))

    {:reply, pe_state, state}
  end

  @doc false
  def handle_call({:load_process_models, models}, _from, state) do
    Enum.each(models, fn m -> CubDB.put(state.process_model_db, m.name, m) end)
    {:reply, state, state}
  end

  @doc false
  def handle_call({:get_process_model, name}, _from, state) do
    {:reply, CubDB.get(state.process_model_db, name), state}
  end

  @doc false
  def handle_call({:load_process_model, process_model}, _from, state) do
    {:reply, CubDB.put(state.process_model_db, process_model.name, process_model), state}
  end

  @doc false
  def handle_call({:clear_then_load_process_models, models}, _from, state) do
    CubDB.clear(state.process_model_db)
    Enum.each(models, fn m -> CubDB.put(state.process_model_db, m.name, m) end)
    {:reply, models, Map.put(state, :process_models, models)}
  end

  def handle_cast({:register_process_instance, uid, pid}, state) do
    process_instances = Map.put(state.process_instances, uid, pid)
    {:noreply, Map.put(state, :process_instances, process_instances)}
  end

  def handle_cast({:insert_completed_process, pe_process}, state) do
    CubDB.put(state.completed_process_db, pe_process.uid, pe_process)
    {:noreply, state}
  end

  def handle_cast({:complete_user_task, ppid, user_task_uid, data}, state) do
    CubDB.delete(state.user_task_db, user_task_uid)
    PE.complete_user_task_and_go(ppid, user_task_uid, data)
    {:noreply, state}
  end

  def handle_cast({:assign_user_task, task, user_id}, state) do
    task = Map.put(task, :assignee, user_id)
    insert_user_task(state, task)
    {:noreply, state}
  end

  def handle_cast(:clear_user_tasks, state) do
    CubDB.clear(state.user_task_db)
    {:noreply, state}
  end

  def handle_cast({:insert_user_task, task}, state) do
    insert_user_task(state, task)
    {:noreply, state}
  end

  defp insert_user_task(state, task) do
    CubDB.put(state.user_task_db, task.uid, task)
  end

  defp get_user_tasks_for_groups_local(groups, state) do
    intersection = fn l1, l2 -> Enum.filter(l2, fn item -> Enum.member?(l1, item) end) end

    CubDB.select(state.user_task_db)
    |> Stream.map(fn {_uid, t} -> t end)
    |> Stream.filter(fn t -> intersection.(groups, t.assigned_groups) end)
    |> Enum.to_list()
  end

  defp get_user_task_by_id(state, uid) do
    CubDB.get(state.user_task_db, uid)
  end

  defp get_user_tasks(state) do
    CubDB.select(state.user_task_db) |> Stream.map(fn {_k, v} -> v end) |> Enum.to_list()
  end
end
