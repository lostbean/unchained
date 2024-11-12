import gleam/option
import gleam/string
import gleeunit
import gleeunit/should
import unchained

pub fn main() {
  gleeunit.main()
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
  |> unchained.run_with("Hey", fn(input, _cfg) {
    input |> should.equal("Hey")
    Ok(unchained.Response("Hello"))
  })
  |> should.be_ok()
  |> should.equal("Hey")

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
  |> unchained.run_with("Hello world", fn(input, _cfg) {
    input |> should.equal("Translate this to French: lost bread")
    Ok(unchained.Response("pain perdu"))
  })
  |> should.be_ok()
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
  |> unchained.run_with("Hello world", fn(input, _cfg) {
    input
    |> should.equal(
      "Hello world
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
  |> should.equal("LOWER CASE")
}
