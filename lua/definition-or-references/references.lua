local methods = require("definition-or-references.methods_state")
local utils = require("definition-or-references.utils")
local log = require("definition-or-references.util.debug")
local config = require("definition-or-references.config")

local function handle_references_response(context)
  log.trace("handle_references_response", "handle_references_response")
  local result_entries = methods.references.result

  if not result_entries or vim.tbl_isempty(result_entries) then
    if
      (methods.definitions.result and #methods.definitions.result > 0)
      and config.get_notify_option("on_definition_no_reference")
    then
      vim.notify("Cursor on definition and no references found")
    elseif
      (not methods.definitions.result or #methods.definitions.result == 0)
      and config.get_notify_option("no_definition_no_reference")
    then
      vim.notify("No definition or references found")
    end
    return
  end

  if #result_entries == 1 then
    if
      methods.definitions.result
      and #methods.definitions.result > 0
      and config.get_notify_option("on_definition_one_reference")
    then
      vim.notify("Cursor on definition and only one reference found")
    elseif
      (not methods.definitions.result or #methods.definitions.result == 0)
      and config.get_notify_option("no_definition_one_reference")
    then
      vim.notify("No definition but single reference found")
    end
    vim.lsp.util.jump_to_location(
      result_entries[1],
      vim.lsp.get_client_by_id(context.client_id).offset_encoding,
      true
    )

    return
  end

  local on_references_result = config.get_config().on_references_result

  if on_references_result then
    return on_references_result(result_entries)
  end

  local handler = vim.lsp.handlers[methods.references.name]

  if not handler then
    handler = function(_, result, ctx)
      local util = vim.lsp.util
      if not util.locations_to_items and util.locations_to_items_via_item_kind then
        util.locations_to_items = util.locations_to_items_via_item_kind
      end
      local client = vim.lsp.get_client_by_id(ctx.client_id)
      local items =
        util.locations_to_items(result or {}, client and client.offset_encoding or "utf-16")
      if not vim.tbl_isempty(items) then
        vim.fn.setqflist({}, " ", { title = "References", items = items })
        vim.cmd("copen")
      else
        vim.notify("No references found", vim.log.levels.INFO)
      end
    end
  end

  handler(nil, result_entries, context)
end

local function send_references_request()
  log.trace("send_references_request", "Starting references request")
  _, methods.references.cancel_function = vim.lsp.buf_request(
    0,
    methods.references.name,
    utils.make_params(),
    function(err, result, context, _)
      log.trace("send_references_request", "Starting references request handling")
      -- sometimes when cancel function was called after request has been fulfilled this would be called
      -- if cancel_function is nil that means that references was cancelled
      if methods.references.cancel_function == nil then
        return
      end

      methods.references.is_pending = false

      if err then
        if config.get_notify_option("errors") then
          vim.notify(err.message, vim.log.levels.ERROR)
        end
        return
      end

      methods.references.result = result

      if not methods.definitions.is_pending then
        log.trace("send_references_request", "handle_references_response")
        handle_references_response(context)
      end
    end
  )

  methods.references.is_pending = true
end

return {
  send_references_request = send_references_request,
  handle_references_response = handle_references_response,
}
