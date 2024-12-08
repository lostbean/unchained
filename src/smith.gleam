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
  type TaskResult, type Tool, type ToolId,
}

// Error handling and recovery
/// ========================================================================
/// Agent behavior implementation
/// ========================================================================
// Agent behavior implementation

pub fn start_default_agent(
  id id: AgentId,
  tools tools: List(Tool),
) -> Result(process.Subject(AgentMessage), AgentError) {
  start_agent(init_agent(id, tools))
}

pub fn start_agent(
  state: AgentState,
) -> Result(process.Subject(AgentMessage), AgentError) {
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

pub fn init_agent(id id: AgentId, tools tools: List(Tool)) -> AgentState {
  types.AgentState(
    id: id,
    status: types.Available,
    current_task: None,
    memory: [],
    tools: tools,
    recovery_strategy: types.RetryWithBackoff(max_retries: 5, base_delay: 1000),
    error_count: 0,
  )
}

pub fn with_recovery_strategy(
  state: AgentState,
  strategy: types.RecoveryStrategy,
) -> AgentState {
  types.AgentState(..state, recovery_strategy: strategy)
}

pub fn send_task_to_agent(agent: Subject(AgentMessage), task: Task) -> Nil {
  actor.send(agent, types.TaskAssignment(task))
}

pub fn run_tool_on_agent(
  agent: Subject(AgentMessage),
  tool_id: ToolId,
  input: Dynamic,
) -> Nil {
  actor.send(agent, types.ToolRequest(tool_id, input))
}

fn handle_task_assignment(state: AgentState, task: Task) -> AgentState {
  case task.add_task(state, task) {
    Ok(new_state) -> new_state
    Error(error) -> agent.handle_error_with_recovery(state, error)
  }
}

fn handle_tool_request(
  state: AgentState,
  tool_id: ToolId,
  params: Dynamic,
) -> AgentState {
  case execute_tool(state, tool_id, params) {
    Ok(result) -> {
      // TODO: apply result to state
      // TODO: log tool execution
      // TODO: send completion notification
      state
    }
    Error(error) -> agent.handle_error_with_recovery(state, error)
  }
}

fn merge_state(state: AgentState, new_state: AgentState) -> AgentState {
  // Merge memory entries
  let memory = list.append(state.memory, new_state.memory)
  // Merge tools
  let tools = list.append(state.tools, new_state.tools)
  types.AgentState(..state, memory: memory, tools: tools)
}

fn handle_completion(state: AgentState, result: TaskResult) -> AgentState {
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
  message: AgentMessage,
  state: AgentState,
) -> actor.Next(AgentMessage, AgentState) {
  let new_state = case message {
    types.TaskAssignment(task) -> {
      handle_task_assignment(state, task)
    }
    types.ToolRequest(tool_id, params) -> {
      handle_tool_request(state, tool_id, params)
    }
    types.StateUpdate(new_state) -> {
      merge_state(state, new_state)
    }
    types.CompletionNotification(result) -> {
      handle_completion(state, result)
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

fn validate_tool(tool: Tool) -> Result(Nil, String) {
  // Check if the tool ID is unique
  // Check if the tool name is unique
  // Check if the handler function is valid
  Ok(Nil)
}

// Tool registration and management
pub fn register_tool(
  state: AgentState,
  tool: Tool,
) -> Result(AgentState, String) {
  case validate_tool(tool) {
    Ok(_) -> {
      Ok(types.AgentState(..state, tools: [tool, ..state.tools]))
    }
    Error(reason) -> Error(reason)
  }
}

fn find_tool(tools: List(Tool), tool_id: ToolId) -> Result(Tool, String) {
  case list.find(tools, fn(tool) { tool.id == tool_id }) {
    Ok(tool) -> Ok(tool)
    Error(_) -> Error("Tool not found")
  }
}

// Helper function for type-safe tool execution
pub fn execute_tool(
  state: AgentState,
  tool_id: ToolId,
  params: Dynamic,
) -> Result(Dynamic, AgentError) {
  case find_tool(state.tools, tool_id) {
    Ok(tool) ->
      tool.handler(params)
      |> result.map_error(types.ToolExecutionError(tool_id, _))
    Error(_) -> Error(types.ToolNotFoundError(tool_id))
  }
}
