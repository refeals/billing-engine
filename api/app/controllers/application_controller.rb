class ApplicationController < ActionController::API
  include ErrorRendering

  # Request bodies are flat JSON objects (`{ "name": … }`), read at the root with
  # `params.permit`; wrapping them under a model key would only duplicate them.
  wrap_parameters false
end
