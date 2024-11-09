# server.R

library(httpuv)
library(jsonlite)

# Helper function to get information about the global environment
get_global_env <- function() {
  lapply(ls(globalenv()), function(obj_name) {
    obj_value <- get(obj_name, envir = globalenv())
    list(
      name = obj_name,
      type = typeof(obj_value),
      class = class(obj_value),
      length = length(obj_value),
      structure = capture.output(str(obj_value, vec.len = 2))
    )
  })
}

# Request handlers
request_handlers <- list(
  greet = function(request) {
    list(status = "success", message = "Hello! -- from R server")
  },
  query_global = function(request) {
    list(status = "success", global_env = get_global_env())
  },
  inspect = function(request) {
    obj_name <- request$obj
    if (exists(obj_name, envir = .GlobalEnv)) {
      obj <- get(obj_name, envir = .GlobalEnv)
      
      # Determine the type of the object
      obj_class <- class(obj)
      if ("data.frame" %in% obj_class || "matrix" %in% obj_class || "data.table" %in% obj_class) {
        obj_df = as.data.frame(obj)
        # For data.frame, matrix, or tibble, return as JSON
        df_json <- toJSON(obj_df, dataframe = "rows", pretty = TRUE)
        list(
          status = "success",
          type = "dataframe",
          data = df_json
        )
      } else {
        # For other object types, return detailed info as a string
        info_str <- paste(
          "Type:", typeof(obj),
          "\nClass:", ifelse(is.null(obj_class), "N/A", paste(obj_class, collapse = ", ")),
          "\nLength:", length(obj),
          "\nStructure:\n", paste(capture.output(str(obj, vec.len = 2)), collapse = "\n"),
          sep = " "
        )
        list(
          status = "success",
          type = "info",
          data = info_str
        )
      }
    } else {
      list(status = "error", message = paste("Object", obj_name, "does not exist!"))
    }
  }
)

# Initialize and start the server
init_server <- function(host = "127.0.0.1", port = 8000, handlers = request_handlers) {
  tryCatch({
    server <- httpuv::startServer(host, port, list(
      call = function(req) {
        # Read the request body
        body <- rawToChar(req$rook.input$read())
        request <- fromJSON(body, simplifyVector = FALSE)
        
        handler <- handlers[[request$type]]
        response <- if (is.function(handler)) {
          do.call(handler, list(request))
        } else {
          list(status = "error", message = "Unknown request type")
        }
        
        list(
          status = 200,
          headers = list("Content-Type" = "application/json"),
          body = toJSON(response, auto_unbox = TRUE, pretty = TRUE, force = TRUE)
        )
      }
    ))
    cat("R Server started on", host, ":", port, "\n")
    list(server = server, port = port)
  }, error = function(e) {
    cat("Failed to start R server:", e$message, "\n")
    NULL
  })
}

# Retrieve the port from environment variable or use default
port_env <- Sys.getenv("PORT")
port <- ifelse(port_env != "", as.integer(port_env), 8000)

# Start the server
server <- init_server(port = port)


