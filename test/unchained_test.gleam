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

  let chain =
    unchained.new()
    |> unchained.add_prompt_template(
      "Translate this to {{ language }}: {{ input }}",
      [],
    )
    |> should.be_ok()
    |> unchained.set_variable("language", "French")
    |> unchained.set_variable("input", "lost bread")
    |> unchained.add_llm(config)
    |> unchained.add_tool(tool)

  // Run the chain
  unchained.run_with(chain, "Hello world", fn(input, _cfg) {
    input |> should.equal("Translate this to French: lost bread")
    Ok(unchained.Response("pain perdu"))
  })
  |> should.be_ok()
  |> should.equal("PAIN PERDU")
}
