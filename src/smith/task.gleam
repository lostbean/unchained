import birl
import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string

import smith/types.{
  type AgentError, type AgentId, type AgentState, type Task, type TaskPriority,
  type TaskResult, type TaskStatus, type ToolId,
}

// Previous imports and type definitions remain the same...

fn generate_task_id() -> String {
  let timestamp = birl.now()
  // let random_suffix = string.slice(string.random_string(8), 0, 8)
  let random_suffix = "xyz"
  string.concat([
    "task_",
    int.to_string(timestamp.wall_time),
    "_",
    random_suffix,
  ])
}

// Helper functions for task management
pub fn create_task(
  name: String,
  description: String,
  priority: TaskPriority,
  sender: AgentId,
  target: AgentId,
  context: Dynamic,
  required_tools: List(ToolId),
) -> Task {
  types.Task(
    id: generate_task_id(),
    name: name,
    description: description,
    priority: priority,
    status: types.Pending,
    created_at: birl.now().wall_time,
    deadline: None,
    dependencies: [],
    sender: sender,
    target: target,
    context: context,
    required_tools: required_tools,
  )
}

pub fn update_task_status(task: Task, new_status: TaskStatus) -> Task {
  types.Task(..task, status: new_status)
}

pub fn create_task_result(
  task: Task,
  output: Dynamic,
  execution_time: Int,
  tools_used: List(ToolId),
) -> TaskResult {
  types.TaskResult(
    task_id: task.id,
    status: task.status,
    output: output,
    execution_time: execution_time,
    tools_used: tools_used,
    error: None,
    metadata: dict.new(),
  )
}

pub fn create_error_result(task: Task, error: AgentError) -> TaskResult {
  types.TaskResult(
    task_id: task.id,
    status: types.Failed(error),
    output: dynamic.from(Nil),
    execution_time: 0,
    tools_used: [],
    error: Some(error),
    metadata: dict.new(),
  )
}

fn has_tool(_state: AgentState, _tool_name: String) -> Bool {
  todo
}

fn validate_dependencies(_dependencies: List(String)) -> Result(a, String) {
  todo
}

fn validate_task_requirements(
  state: AgentState,
  task: Task,
) -> Result(Nil, AgentError) {
  // Check if agent has all required tools
  let has_tools =
    list.all(task.required_tools, fn(tool_id) { has_tool(state, tool_id) })

  case has_tools {
    False -> Error(types.StateError("Missing required tools"))
    True -> {
      // Check if all dependencies are completed
      case validate_dependencies(task.dependencies) {
        Ok(_) -> Ok(Nil)
        Error(reason) -> Error(types.TaskExecutionError(task.id, reason))
      }
    }
  }
}

// Task validation and checking
pub fn can_execute_task(
  state: AgentState,
  task: Task,
) -> Result(Bool, AgentError) {
  case validate_task_requirements(state, task) {
    Ok(_) -> {
      case state.status {
        types.Available -> Ok(True)
        types.Busy(count) -> {
          Ok(count < 8)
        }
        _ -> Ok(False)
      }
    }
    Error(error) -> Error(error)
  }
}

// Task queue management
pub fn add_task(state: AgentState, task: Task) -> Result(AgentState, AgentError) {
  case can_execute_task(state, task) {
    Ok(True) -> {
      let new_state =
        types.AgentState(
          ..state,
          current_task: Some(task),
          status: case state.status {
            types.Available -> types.Busy(1)
            types.Busy(count) -> types.Busy(count + 1)
            other -> other
          },
        )

      Ok(new_state)
    }
    Error(_) -> todo
    Ok(False) -> todo
  }
}

pub fn complete_task(state: AgentState, result: TaskResult) -> AgentState {
  case state.current_task {
    Some(task) -> {
      case task.id == result.task_id {
        True -> {
          types.AgentState(
            ..state,
            current_task: None,
            status: case state.status {
              types.Busy(1) -> types.Available
              types.Busy(count) -> types.Busy(count - 1)
              other -> other
            },
          )
        }
        False -> state
      }
    }
    None -> state
  }
}
