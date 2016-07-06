defmodule Wit do
  @moduledoc """
  The client for the WIT API that contains the low-level functions for APIs such as /message and /converse.
  It also contains the high level function such as `run_actions` to run module implementing the actions
  and also the `interactive` API that runs the actions by getting message from the console.
  """

  require Logger
  alias Wit.Client
  alias Wit.Client.Deserializer
  alias Wit.Models.Response.Converse
  alias Wit.Models.Response.Message

  @doc """
  Calls the /message API
  """
  @spec message(String.t, String.t, map, String.t, String.t, integer) :: {:ok, Message.t} | {:error, String.t, map}
  def message(access_token, text, context \\ %{}, thread_id \\ "", msg_id \\ "", total_outcomes \\ 1) do

    Client.message(access_token, text, thread_id, msg_id, context, total_outcomes)
    |> Deserializer.deserialize_message
  end

  @doc """
  Calls the /converse API
  """
  @spec converse(String.t, String.t, String.t, map) :: {:ok, Converse.t} | {:error, String.t, map}
  def converse(access_token, session_id, text \\ "", context \\ %{}) do

    ret = Client.converse(access_token, session_id, text, context)
    case ret do
      {:stopped, _} -> Deserializer.deserialize_converse("{}")
      {:error, _} -> Deserializer.deserialize_converse("{}")
      _ -> Deserializer.deserialize_converse(ret)
    end
  end

  @doc """
  Calls the /converse API and sses the default and custome actions defined in the `module`
  to return back the response to the /converse API and update the context until the /converse
  API returns back stop or `max_steps` have reached (whichever comes first).
  """
  @spec run_actions(String.t, String.t, atom, String.t, map, integer, map) :: any
  def run_actions(access_token, session_id, module, text \\ "", context \\ %{}, max_steps \\ 5, options \\ %{})
  def run_actions(_access_token, _session_id, _module, _text, context, max_steps, _options) when max_steps <= 0 do
    {:error, :invalid_max_steps, context}
  end
  def run_actions(access_token, session_id, module, text, context, max_steps, options) do

    Logger.debug "Running actions: Step remaining #{max_steps}"
    resp = converse(access_token, session_id, text, context)

    case context do
      %{stopped: true} ->
        Logger.debug("Stopping further converse requests")
        resp
      _ ->
        Logger.debug inspect(resp)
        case resp do
          {:ok, conv} -> run_action(access_token, session_id, module, context, conv, max_steps-1, options)
          {:error, error, resp} -> run_action(:error, session_id, module, context, {error, resp}, options)
          other -> other
        end
    end
  end

  @doc """
  Calls the `run_actions` using the text gotten from console and keeps on running till user exits.
  The user can exit by pressing `Enter` which will prompt the user to quit or not.
  """
  @spec interactive(String.t, String.t, atom, map) :: {:ok, map}
  def interactive(access_token, session_id, module, context \\ %{}) do
    text = IO.gets "> "
    interactive(text, access_token, session_id, module, context)
  end

  defp interactive("\n", access_token, session_id, module, context) do
    text = IO.gets "> Do you want to exit? (y/n) "
    case text do
      "y\n" -> {:ok, context}
      "n\n" -> interactive(access_token, session_id, module, context)
      _ -> interactive("\n", access_token, session_id, module, context)
    end
  end
  defp interactive(text, access_token, session_id, module, context) do
    {:ok, context} = run_actions(access_token, session_id, module, text, context)
    interactive(access_token, session_id, module, context)
  end

  defp run_action(_access_token, _session_id, _module, context, _resp, 0, _options) do
    Logger.error  "Force stoped after reaching max steps"
    {:error, :max_steps_reached, context}
  end

  defp run_action(access_token, session_id, module, context, %Converse{type: "msg"} = resp, max_steps, options) do
    Logger.debug "Got converse type \"msg\""

    context = apply(module, :call_action, ["say", session_id, context, resp, options])
    run_actions(access_token, session_id, module, "", context, max_steps, options)
  end

  defp run_action(access_token, session_id, module, context, %Converse{type: "merge"} = resp, max_steps, options) do
    Logger.debug "Got converse type \"merge\""
    context = apply(module, :call_action, ["merge", session_id, context, resp, options])
    run_actions(access_token, session_id, module, "", context, max_steps, options)
  end

  defp run_action(access_token, session_id, module, context, %Converse{type: "action"} = resp, max_steps, options) do
    Logger.debug "Got converse type \"action\""
    context = apply(module, :call_action, [resp.action, session_id, context, options])
    run_actions(access_token, session_id, module, "", context, max_steps, options)
  end

  defp run_action(_access_token, _session_id, _module, context, %Converse{type: "stop"}, _max_steps, _options) do
    Logger.debug "Got converse type \"stop\""
    {:ok, context}
  end

  defp run_action(:error, session_id, module, context, error, options) do
    Logger.debug "Calling the error handler"
    apply(module, :call_action, ["error", session_id, context, error, options])
  end
end
