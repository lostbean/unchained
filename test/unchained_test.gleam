import gleam/list
import gleam/option
import gleam/string
import gleeunit
import gleeunit/should
import unchained

pub fn main() {
  gleeunit.main()
}

pub fn history_test() {
  let tool =
    unchained.Tool(
      name: "format",
      description: "Format the translation",
      function: fn(x) { Ok(string.uppercase(x)) },
    )

  let config =
    unchained.LLMConfig(
      host: "localhost:11434",
      model: "llama3.2:3b",
      temperature: 0.0,
    )

  // Run empty chain
  let eval =
    unchained.new()
    |> unchained.add_prompt_template("Test 1")
    |> should.be_ok()
    |> unchained.add_tool(tool)
    |> unchained.add_llm(config)
    |> unchained.run_with(fn(input, _cfg) {
      input |> should.equal("TEST 1")
      Ok(unchained.Response("test 2"))
    })
    |> should.be_ok()

  eval
  |> unchained.get_eval_memory()
  |> fn(x) { x.history }
  |> list.map(fn(x) { x.input })
  |> should.equal(["Test 1", "TEST 1"])

  eval
  |> unchained.get_eval_memory()
  |> fn(x) { x.history }
  |> list.map(fn(x) { x.output })
  |> should.equal(["TEST 1", "test 2"])

  eval
  |> unchained.get_eval_output()
  |> should.equal("test 2")
}

pub fn chain_test() {
  let tool =
    unchained.Tool(
      name: "format",
      description: "Format the translation",
      function: fn(x) { Ok(string.uppercase(x)) },
    )

  let config =
    unchained.LLMConfig(
      host: "localhost:11434",
      model: "llama3.2:3b",
      temperature: 0.0,
    )

  // Run empty chain
  unchained.new()
  |> unchained.run_with(fn(input, _cfg) {
    input |> should.equal("Hey")
    Ok(unchained.Response("Hello"))
  })
  |> should.be_ok()
  |> unchained.get_eval_output()
  |> should.equal("")

  // Run the chain
  unchained.new()
  |> unchained.add_prompt_template(
    "Translate this to {{ language }}: {{ input }}",
  )
  |> should.be_ok()
  |> unchained.set_variable("language", "French")
  |> unchained.set_variable("input", "lost bread")
  |> unchained.add_llm(config)
  |> unchained.add_tool(tool)
  |> unchained.run_with(fn(input, _cfg) {
    input |> should.equal("Translate this to French: lost bread")
    Ok(unchained.Response("pain perdu"))
  })
  |> should.be_ok()
  |> unchained.get_eval_output()
  |> should.equal("PAIN PERDU")

  // Run the chain with tool selection
  unchained.new()
  |> unchained.set_variable("input", "test")
  |> unchained.add_llm_with_tool_selection(
    config,
    "Here is the list of tools available to {{ input }}:
{{#each tools}}
  Function Name: {{name}}
  Function Description: {{description}}
  ---
{{/each}}

To use too call it with:

Tool Selected: <tool name>
",
    [
      unchained.ToolSelector(
        fn(some_input) {
          case some_input {
            "e" -> option.Some("lower case")
            _ -> option.None
          }
        },
        tool,
      ),
    ],
  )
  |> should.be_ok()
  |> unchained.add_tool(tool)
  |> unchained.run_with(fn(input, _cfg) {
    input
    |> should.equal(
      "
Here is the list of tools available to test:

  Function Name: format
  Function Description: Format the translation
  ---


To use too call it with:

Tool Selected: <tool name>
",
    )
    Ok(unchained.Response("e"))
  })
  |> should.be_ok()
  |> unchained.get_eval_output()
  |> should.equal("LOWER CASE")
}
