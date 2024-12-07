import birl
import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/erlang/process.{type Pid}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/otp/supervisor
import gleam/result
import gleam/string

// Type definitions for the core components
pub type AgentId =
  String

pub type ToolId =
  String

// Custom types for agent messages
pub type AgentMessage {
  TaskAssignment(task: Task)
  ToolRequest(tool: ToolId, params: Dynamic)
  StateUpdate(state: AgentState)
  CompletionNotification(result: TaskResult)
}

pub type MemoryEntry {
  MemoryEntry(key: String, value: Dynamic)
}

pub type RecoveryStrategy {
  RetryWithBackoff(max_retries: Int, base_delay: Int)
  DelegateToFallback(fallback_agent: AgentId)
  RestartClean
  NotifyAndWait
}

// Agent state definition
pub type AgentState {
  AgentState(
    id: AgentId,
    status: Status,
    current_task: Option(Task),
    memory: List(MemoryEntry),
    tools: List(Tool),
    recovery_strategy: RecoveryStrategy,
    error_count: Int,
  )
}

// Tool definition
pub type Tool {
  Tool(
    id: ToolId,
    name: String,
    description: String,
    handler: fn(Dynamic) -> Result(Dynamic, String),
  )
}

// Previous imports and type definitions remain the same...

// Task related types
pub type TaskPriority {
  Low
  Medium
  High
  Critical
}

pub type TaskStatus {
  Pending
  InProgress(started_at: Int)
  Completed(completed_at: Int)
  Failed(error: AgentError)
  Cancelled(reason: String)
}

pub type Task {
  Task(
    id: String,
    name: String,
    description: String,
    priority: TaskPriority,
    status: TaskStatus,
    created_at: Int,
    deadline: Option(Int),
    dependencies: List(String),
    // List of task IDs this task depends on
    sender: AgentId,
    // Agent that created the task
    target: AgentId,
    // Agent meant to execute the task
    context: Dynamic,
    // Task-specific data
    required_tools: List(ToolId),
  )
}

pub type TaskResult {
  TaskResult(
    task_id: String,
    status: TaskStatus,
    output: Dynamic,
    execution_time: Int,
    tools_used: List(ToolId),
    error: Option(AgentError),
    metadata: Dict(String, Dynamic),
  )
}

// Agent status
pub type Status {
  Available
  Busy(task_count: Int)
  Paused(reason: String)
  Maintenance
  ShuttingDown
  AgentError(error: AgentError)
}

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
  Task(
    id: generate_task_id(),
    name: name,
    description: description,
    priority: priority,
    status: Pending,
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
  Task(..task, status: new_status)
}

pub fn create_task_result(
  task: Task,
  output: Dynamic,
  execution_time: Int,
  tools_used: List(ToolId),
) -> TaskResult {
  TaskResult(
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
  TaskResult(
    task_id: task.id,
    status: Failed(error),
    output: dynamic.from(Nil),
    execution_time: 0,
    tools_used: [],
    error: Some(error),
    metadata: dict.new(),
  )
}

// Status management functions
pub fn update_agent_status(state: AgentState, new_status: Status) -> AgentState {
  AgentState(..state, status: new_status)
}

pub fn is_available(state: AgentState) -> Bool {
  case state.status {
    Available -> True
    _ -> False
  }
}

pub fn is_busy(state: AgentState) -> Bool {
  case state.status {
    Busy(_) -> True
    _ -> False
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
        Available -> Ok(True)
        Busy(count) -> {
          Ok(count < 8)
        }
        _ -> Ok(False)
      }
    }
    Error(error) -> Error(error)
  }
}

fn has_tool(state: AgentState, tool_name: String) -> Bool {
  todo
}

fn validate_dependencies(dependencies: List(String)) -> Result(a, String) {
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
    False -> Error(StateError("Missing required tools"))
    True -> {
      // Check if all dependencies are completed
      case validate_dependencies(task.dependencies) {
        Ok(_) -> Ok(Nil)
        Error(reason) -> Error(TaskExecutionError(task.id, reason))
      }
    }
  }
}

// Task queue management
pub fn add_task(state: AgentState, task: Task) -> Result(AgentState, AgentError) {
  case can_execute_task(state, task) {
    Ok(True) -> {
      let new_state =
        AgentState(
          ..state,
          current_task: Some(task),
          status: case state.status {
            Available -> Busy(1)
            Busy(count) -> Busy(count + 1)
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
          AgentState(
            ..state,
            current_task: None,
            status: case state.status {
              Busy(1) -> Available
              Busy(count) -> Busy(count - 1)
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

/// ========================================================================
/// Agent Error
/// ========================================================================
// Comprehensive error types

pub type AgentError {
  // Tool related errors
  ToolExecutionError(tool_id: ToolId, reason: String)
  ToolNotFoundError(tool_id: ToolId)
  ToolInitializationError(tool_id: ToolId, reason: String)

  // Task related errors
  TaskExecutionError(task_id: String, reason: String)
  TaskValidationError(task_id: String, reason: String)
  TaskTimeoutError(task_id: String, timeout: Int)
  TaskDependencyError(task_id: String, dependency_id: String)

  // State related errors
  StateError(reason: String)
  InvalidStateTransition(from: Status, to: Status)

  // Resource errors
  ResourceExhausted(resource: String)
  MemoryLimitExceeded(current: Int, limit: Int)
  ConcurrencyLimitExceeded(current: Int, limit: Int)

  // Communication errors
  CommunicationError(target: AgentId, reason: String)
  MessageDeliveryError(message_id: String, reason: String)

  // System errors
  SupervisorError(reason: String)
  InitializationError(reason: String)
  ShutdownError(reason: String)

  // Recovery errors
  RecoveryStrategyError(strategy: RecoveryStrategy, reason: String)
  RetryLimitExceeded(attempts: Int, max_retries: Int)

  // Custom errors
  CustomError(code: String, reason: String, metadata: Dict(String, Dynamic))
}

pub fn format_status(status: Status) -> String {
  case status {
    Available -> "Available"
    Busy(_) -> "Busy"
    Paused(_) -> "Paused"
    Maintenance -> "Maintenance"
    ShuttingDown -> "Shutting down"
    AgentError(_) -> "Error"
  }
}

pub fn format_recovery_strategy(strategy: RecoveryStrategy) -> String {
  case strategy {
    RetryWithBackoff(_, _) -> "Retry with backoff"
    DelegateToFallback(_) -> "Delegate to fallback"
    RestartClean -> "Restart clean"
    NotifyAndWait -> "Notify and wait"
  }
}

// Error handling utilities
pub fn format_error(error: AgentError) -> String {
  case error {
    ToolExecutionError(tool_id, reason) ->
      string.concat(["Tool execution failed for ", tool_id, ": ", reason])

    ToolNotFoundError(tool_id) -> string.concat(["Tool not found: ", tool_id])

    ToolInitializationError(tool_id, reason) ->
      string.concat(["Failed to initialize tool ", tool_id, ": ", reason])

    TaskExecutionError(task_id, reason) ->
      string.concat(["Task execution failed for ", task_id, ": ", reason])

    TaskValidationError(task_id, reason) ->
      string.concat(["Task validation failed for ", task_id, ": ", reason])

    TaskTimeoutError(task_id, timeout) ->
      string.concat([
        "Task ",
        task_id,
        " timed out after ",
        int.to_string(timeout),
        "ms",
      ])

    TaskDependencyError(task_id, dependency_id) ->
      string.concat([
        "Task ",
        task_id,
        " failed due to dependency ",
        dependency_id,
      ])

    StateError(reason) -> string.concat(["State error: ", reason])

    InvalidStateTransition(from, to) ->
      string.concat([
        "Invalid state transition from ",
        format_status(from),
        " to ",
        format_status(to),
      ])

    ResourceExhausted(resource) ->
      string.concat(["Resource exhausted: ", resource])

    MemoryLimitExceeded(current, limit) ->
      string.concat([
        "Memory limit exceeded: ",
        int.to_string(current),
        "/",
        int.to_string(limit),
        " bytes",
      ])

    ConcurrencyLimitExceeded(current, limit) ->
      string.concat([
        "Concurrency limit exceeded: ",
        int.to_string(current),
        "/",
        int.to_string(limit),
        " tasks",
      ])

    CommunicationError(target, reason) ->
      string.concat(["Communication failed with agent ", target, ": ", reason])

    MessageDeliveryError(message_id, reason) ->
      string.concat(["Failed to deliver message ", message_id, ": ", reason])

    SupervisorError(reason) -> string.concat(["Supervisor error: ", reason])

    InitializationError(reason) ->
      string.concat(["Initialization failed: ", reason])

    ShutdownError(reason) -> string.concat(["Shutdown failed: ", reason])

    RecoveryStrategyError(strategy, reason) ->
      string.concat([
        "Recovery strategy ",
        format_recovery_strategy(strategy),
        " failed: ",
        reason,
      ])

    RetryLimitExceeded(attempts, max_retries) ->
      string.concat([
        "Retry limit exceeded: ",
        int.to_string(attempts),
        "/",
        int.to_string(max_retries),
        " attempts",
      ])

    CustomError(code, reason, _) ->
      string.concat(["Error ", code, ": ", reason])
  }
}

// Error severity levels
pub type ErrorSeverity {
  CriticalError
  HighError
  MediumError
  LowError
}

pub fn get_error_severity(error: AgentError) -> ErrorSeverity {
  case error {
    InitializationError(_) -> CriticalError
    SupervisorError(_) -> CriticalError
    MemoryLimitExceeded(_, _) -> CriticalError
    ConcurrencyLimitExceeded(_, _) -> CriticalError

    TaskExecutionError(_, _) -> HighError
    CommunicationError(_, _) -> HighError
    StateError(_) -> HighError
    InvalidStateTransition(_, _) -> HighError
    RecoveryStrategyError(_, _) -> HighError
    ShutdownError(_) -> HighError

    ToolExecutionError(_, _) -> MediumError
    TaskTimeoutError(_, _) -> MediumError
    ResourceExhausted(_) -> MediumError
    MessageDeliveryError(_, _) -> MediumError
    RetryLimitExceeded(_, _) -> MediumError

    ToolInitializationError(_, _) -> LowError
    TaskValidationError(_, _) -> LowError
    ToolNotFoundError(_) -> LowError
    CustomError(_, _, _) -> LowError
    TaskDependencyError(_, _) -> LowError
  }
}

// Error handling and recovery
pub fn handle_error_with_recovery(
  state: AgentState,
  error: AgentError,
) -> AgentState {
  // Log the error
  // log_error(state.id, error)

  // Update error metrics
  // let state = update_error_metrics(state, error)

  // Check if we should attempt recovery based on severity
  case get_error_severity(error) {
    CriticalError -> {
      notify_supervisor(state.id, error)
      AgentState(..state, status: AgentError(error))
    }

    HighError | MediumError -> {
      attempt_recovery(state, error)
    }

    LowError -> {
      // For low severity, just log and continue
      state
    }
  }
}

pub fn notify_supervisor(agent_id: AgentId, error: AgentError) {
  // supervisor.notify(agent_id, error)
  todo
}

pub fn calculate_backoff_delay(base_delay: Int, error_count: Int) -> Int {
  // TODO: review this
  base_delay * { int.bitwise_shift_left(error_count, 2) }
}

pub fn retry_failed_operation(
  state: AgentState,
  error: AgentError,
) -> AgentState {
  let new_state = AgentState(..state, error_count: state.error_count + 1)
  case state.current_task {
    Some(task) -> {
      let task_result = create_error_result(task, error)
      let new_state = complete_task(new_state, task_result)
      new_state
    }
    None -> new_state
  }
}

pub fn delegate_to_fallback(
  state: AgentState,
  fallback_agent: AgentId,
  error: AgentError,
) -> AgentState {
  // supervisor.delegate(state.id, fallback_agent, error)
  todo
}

pub fn pause_agent(state: AgentState, reason: String) -> AgentState {
  AgentState(..state, status: Paused(reason), current_task: None)
}

fn attempt_recovery(state: AgentState, error: AgentError) -> AgentState {
  case state.recovery_strategy {
    RetryWithBackoff(max_retries, base_delay) -> {
      case state.error_count <= max_retries {
        True -> {
          let delay = calculate_backoff_delay(base_delay, state.error_count)
          process.sleep(delay)
          retry_failed_operation(state, error)
        }
        False ->
          AgentState(
            ..state,
            status: AgentError(RetryLimitExceeded(
              state.error_count,
              max_retries,
            )),
          )
      }
    }

    DelegateToFallback(fallback_agent) -> {
      delegate_to_fallback(state, fallback_agent, error)
    }

    RestartClean -> {
      // try new_state = cleanup_state(state)
      // try new_state = reinitialize_agent(new_state)
      // Ok(new_state)
      todo
    }

    NotifyAndWait -> {
      notify_supervisor(state.id, error)
      pause_agent(state, "Waiting for manual intervention")
    }
  }
}

/// ========================================================================
/// Agent behavior implementation
/// ========================================================================
// Agent behavior implementation

pub fn start_agent(
  id: AgentId,
  tools: List(Tool),
) -> Result(process.Subject(AgentMessage), actor.StartError) {
  actor.start(init_agent(id, tools), handle_message)
}

fn init_agent(id: AgentId, tools: List(Tool)) -> AgentState {
  AgentState(
    id: id,
    status: Available,
    current_task: None,
    memory: [],
    tools: tools,
    recovery_strategy: RetryWithBackoff(max_retries: 5, base_delay: 1000),
    error_count: 0,
  )
}

fn handle_task_assignment(state: AgentState, task: Task) -> AgentState {
  case add_task(state, task) {
    Ok(new_state) -> new_state
    Error(error) -> handle_error_with_recovery(state, error)
  }
}

fn handle_tool_request(
  state: AgentState,
  tool_id: ToolId,
  params: Dynamic,
) -> AgentState {
  case execute_tool(state, tool_id, params) {
    Ok(result) -> {
      // log_tool_execution(state.id, tool_id, params, result)
      state
    }
    Error(error) -> handle_error_with_recovery(state, error)
  }
}

fn merge_state(state: AgentState, new_state: AgentState) -> AgentState {
  // Merge memory entries
  let memory = list.append(state.memory, new_state.memory)
  // Merge tools
  let tools = list.append(state.tools, new_state.tools)
  AgentState(..state, memory: memory, tools: tools)
}

fn handle_completion(state: AgentState, result: TaskResult) -> AgentState {
  case state.current_task {
    Some(task) -> {
      case task.id == result.task_id {
        True -> {
          let new_state = complete_task(state, result)
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
    TaskAssignment(task) -> {
      handle_task_assignment(state, task)
    }
    ToolRequest(tool_id, params) -> {
      handle_tool_request(state, tool_id, params)
    }
    StateUpdate(new_state) -> {
      merge_state(state, new_state)
    }
    CompletionNotification(result) -> {
      handle_completion(state, result)
    }
  }

  case new_state.status {
    AgentError(_) -> actor.Stop(process.Normal)
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
      Ok(AgentState(..state, tools: [tool, ..state.tools]))
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
      tool.handler(params) |> result.map_error(ToolExecutionError(tool_id, _))
    Error(_) -> Error(ToolNotFoundError(tool_id))
  }
}
