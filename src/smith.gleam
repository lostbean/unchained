import gleam/dynamic.{type Dynamic}
import gleam/erlang/process.{type Pid, type Subject}
import gleam/list
import gleam/option.{None, Some}
import gleam/otp/actor
import gleam/result
import gleam/string

import smith/agent
import smith/task
import smith/types.{
  type AgentError, type AgentId, type AgentMessage, type AgentState, type Task,
  type TaskResult, type ToolSet,
}

pub type Agent(state, tool) =
  Subject(AgentMessage(state, tool))

// Error handling and recovery
/// ========================================================================
/// Agent behavior implementation
/// ========================================================================
// Agent behavior implementation

pub fn start_default_agent(
  id id: AgentId,
  tools tools: ToolSet(state, tool),
  initial_state init_st: state,
) -> Result(process.Subject(AgentMessage(state, tool)), AgentError) {
  start_agent(init_agent(id, tools, init_st))
}

pub fn start_agent(
  state: AgentState(state, tool),
) -> Result(process.Subject(AgentMessage(state, tool)), AgentError) {
  actor.start(state, handle_message)
  |> result.map_error(fn(err) {
    types.InitializationError(
      "Failed to start agent_id: '"
      <> state.id
      <> "', reason: "
      <> string.inspect(err),
    )
  })
}

pub fn init_agent(
  id id: AgentId,
  tools tools: ToolSet(state, tool),
  initial_state init_st: state,
) -> AgentState(state, tool) {
  types.AgentState(
    id: id,
    status: types.Available,
    current_task: None,
    memory: [],
    state: init_st,
    tools: tools,
    recovery_strategy: types.RetryWithBackoff(max_retries: 5, base_delay: 1000),
    error_count: 0,
  )
}

pub fn with_recovery_strategy(
  state: AgentState(state, tool),
  strategy: types.RecoveryStrategy,
) -> AgentState(state, tool) {
  types.AgentState(..state, recovery_strategy: strategy)
}

pub fn send_task_to_agent(agent: Agent(state, tool), task: Task) -> Nil {
  actor.send(agent, types.TaskAssignment(task))
}

pub fn run_tool_on_agent(agent: Agent(state, tool), input: tool) -> Nil {
  actor.send(agent, types.ApplyTool(input))
}

fn handle_task_assignment(
  state: AgentState(state, tool),
  task: Task,
) -> AgentState(state, tool) {
  case task.add_task(state, task) {
    Ok(new_state) -> new_state
    Error(error) -> agent.handle_error_with_recovery(state, error)
  }
}

fn handle_tool_request(
  state: AgentState(state, tool),
  params: Dynamic,
) -> AgentState(state, tool) {
  case execute_tool(state, params) {
    Ok(result) -> {
      // TODO: apply result to state
      // TODO: log tool execution
      // TODO: send completion notification
      state
    }
    Error(error) -> agent.handle_error_with_recovery(state, error)
  }
}

fn merge_state(
  state: AgentState(state, tool),
  new_state: AgentState(state, tool),
) -> AgentState(state, tool) {
  let memory = list.append(state.memory, new_state.memory)
  types.AgentState(..state, memory: memory, state: new_state.state)
}

fn handle_completion(
  state: AgentState(state, tool),
  result: TaskResult,
) -> AgentState(state, tool) {
  case state.current_task {
    Some(task) -> {
      case task.id == result.task_id {
        True -> {
          let new_state = task.complete_task(state, result)
          // log_task_completion(state.id, task, result)
          new_state
        }
        False -> state
      }
    }
    None -> state
  }
}

// Message handling
pub fn handle_message(
  message: AgentMessage(state, tool),
  state: AgentState(state, tool),
) -> actor.Next(AgentMessage(state, tool), AgentState(state, tool)) {
  let new_state = case message {
    types.TaskAssignment(task) -> {
      handle_task_assignment(state, task)
    }
    types.FindAndApplyTool(params) -> {
      handle_tool_request(state, params)
    }
    types.StateUpdate(new_state) -> {
      merge_state(state, new_state)
    }
    types.CompletionNotification(result) -> {
      handle_completion(state, result)
    }
    types.ApplyTool(tool) -> {
      types.AgentState(
        ..state,
        state: state.tools.actions(tool, state.memory, state.state),
      )
    }
  }

  case new_state.status {
    types.AgentError(_) -> actor.Stop(process.Normal)
    _ -> actor.continue(new_state)
  }
}

// Supervisor implementation
pub fn start_supervisor() -> Result(Pid, String) {
  // supervisor.new()
  // |> SupervisorSpec.add_worker("agent_registry", fn() { Registry.start() })
  // |> SupervisorSpec.start()
  todo
}

// Helper function for type-safe tool execution
pub fn execute_tool(
  state: AgentState(state, tool),
  params: Dynamic,
) -> Result(state, AgentError) {
  case state.tools.decoder.dyn_decoder(params) {
    Ok(tool) ->
      state.tools.actions(tool, state.memory, state.state)
      |> Ok
    Error(err) -> Error(types.ToolNotFoundError(err))
  }
}
