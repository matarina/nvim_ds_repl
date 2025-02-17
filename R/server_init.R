# server_init.R

# Load necessary libraries
library(httpuv)
library(jsonlite)
library(httpgd)


format_line <- function(attr_name, value) {
  sprintf("%-15s║ %s", attr_name, as.character(value))
}

format_content <- function(attr_name, value) {
  paste0(paste0(rep("▶", 4), collapse = ""), "\\n", value)
}

inspect_vector <- function(obj) {
  # Collect basic information
  info <- c(
    format_line("Type", typeof(obj)),
    format_line("Class", class(obj)),
    format_line("Length", length(obj)),
    format_line("Mode", mode(obj))
  )
  
  # Add attributes if any exist
  if (length(attributes(obj)) > 0) {
    info <- c(info, 
             format_line("Attributes", paste(names(attributes(obj)), collapse = ", ")))
  }
  
  # Add summary for numeric vectors
  if (is.numeric(obj)) {
    stats <- summary(obj)
    info <- c(info,
             format_line("Summary", paste(names(stats), stats, sep = ": ", collapse = ", ")))
  }
  
  # Add levels for factors
  if (is.factor(obj)) {
    info <- c(info,
             format_line("Levels", paste(levels(obj), collapse = ", ")))
  }
  
  # Add content preview
  preview <- if(length(obj) > 10) 
    paste0(paste(head(obj, 10), collapse = " "), "...") 
  else 
    paste(obj, collapse = " ")
  
  info <- c(info, format_content("Content", preview))
  
  paste(info, collapse = "\\n")
}

inspect_matrix <- function(obj) {
  # Set options for wider display
  current_width <- getOption("width")
  options(width = 200)  # Temporarily increase display width

  info <- c(
    format_line("Type", "Matrix"),
    format_line("Dimensions", paste(dim(obj), collapse = " x ")),
    format_line("Storage Mode", storage.mode(obj))
  )
  
  # Add numeric summary
  if (is.numeric(obj)) {
    stats <- summary(as.vector(obj))
    info <- c(info,
             format_line("Summary", paste(names(stats), stats, sep = ": ", collapse = ", ")))
  }
  
  # Create preview matrix
  preview_mat <- obj
  
  # Handle wide matrices (columns)
  if (ncol(preview_mat) > 200) {
    first_cols <- preview_mat[, 1:10, drop = FALSE]
    last_cols <- preview_mat[, (ncol(preview_mat)-9):ncol(preview_mat), drop = FALSE]
    sep_col <- matrix("...", nrow = nrow(preview_mat), ncol = 1)
    colnames(sep_col) <- "..."
    preview_mat <- cbind(first_cols, sep_col, last_cols)
  }
  
  # Handle long matrices (rows)
  if (nrow(preview_mat) > 200) {
    top_rows <- preview_mat[1:10, , drop = FALSE]
    bottom_rows <- preview_mat[(nrow(preview_mat)-9):nrow(preview_mat), , drop = FALSE]
    sep_row <- matrix("...", nrow = 1, ncol = ncol(preview_mat))
    preview_mat <- rbind(top_rows, sep_row, bottom_rows)
  }
  
  # Capture formatted preview
  preview <- capture.output({
    print(preview_mat, right = FALSE)
  })
  
  # Reset display width
  options(width = current_width)
  
  info <- c(info, format_content("Content", paste(preview, collapse = "\\n")))
  paste(info, collapse = "\\n")
}

#
# inspect_matrix <- function(obj) {
#   info <- c(
#     format_line("Type", "Matrix"),
#     format_line("Dimensions", paste(dim(obj), collapse = " x ")),
#     format_line("Storage Mode", storage.mode(obj))
#   )
#
#   if (is.numeric(obj)) {
#     info <- c(info,
#              format_line("Summary", paste(summary(as.vector(obj)), collapse = ", ")))
#   }
#
#   preview <- capture.output(print(if(nrow(obj) > 6) obj[1:6,] else obj))
#   info <- c(info, format_content("Content", paste(preview, collapse = "\\n")))
#
#   paste(info, collapse = "\\n")
# }
#

inspect_dataframe <- function(obj) {
  # Set options for wider display
  current_width <- getOption("width")
  options(width = 200)  # Temporarily increase display width
  
  
  info <- c(
    format_line("Type", "Data Frame"),
    format_line("Dimensions", paste(dim(obj), collapse = " x ")),
    format_line("Column Names", paste(names(obj), collapse = ", ")),
    format_line("Column Types", paste(sapply(obj, class), collapse = ", "))
  )
  
  # NA counts per column
  na_counts <- sapply(obj, function(x) sum(is.na(x)))
  if (sum(na_counts) > 0) {
    info <- c(info,
             format_line("NA counts", paste(names(na_counts), na_counts, sep = ": ", collapse = ", ")))
  }
  
  # Structure information
  str_output <- capture.output(str(obj))
  info <- c(info, format_line("Structure", paste(str_output[1], collapse = "")))
  
  # Data preview with formatting
  preview_df <- obj
  
  # Handle wide dataframes (columns)
  if (ncol(preview_df) > 200) {
    first_cols <- preview_df[, 1:10, drop = FALSE]
    last_cols <- preview_df[, (ncol(preview_df)-9):ncol(preview_df), drop = FALSE]
    sep_col <- data.frame("..." = rep("...", nrow(preview_df)))
    preview_df <- cbind(first_cols, sep_col, last_cols)
  }
  
  # Handle long dataframes (rows)
  if (nrow(preview_df) > 200) {
    top_rows <- head(preview_df, 10)
    bottom_rows <- tail(preview_df, 10)
    sep_row <- as.data.frame(lapply(preview_df, function(x) "..."))
    preview_df <- rbind(top_rows, sep_row, bottom_rows)
  }
  
  # Format the preview with proper spacing
  preview <- capture.output({
    print.data.frame(preview_df, row.names = TRUE, right = FALSE)
  })
  
  # Reset options
  options(width = current_width)
  
  info <- c(info, format_content("Content", paste(preview, collapse = "\\n")))
  paste(info, collapse = "\\n")
}



inspect_list <- function(obj) {
  info <- c(
    format_line("Type", "List"),
    format_line("Length", length(obj)),
    format_line("Names", paste(names(obj), collapse = ", "))
  )
  
  # Element types
  element_types <- sapply(obj, function(x) class(x)[1])
  info <- c(info,
           format_line("Element Types", paste(names(element_types), element_types, sep = ": ", collapse = ", ")))
  
  # Structure preview
  preview <- capture.output(str(obj, max.level = 2))
  info <- c(info, format_content("Structure", paste(preview, collapse = "\\n")))
  
  paste(info, collapse = "\\n")
}


r_inspecter <- function(obj) {
  # Add a flag to track if it was originally a tbl_df
  is_tibble <- inherits(obj, "tbl_df")
  
  if (is_tibble) {
    obj <- as.data.frame(obj)
  }

  # Get the inspection result based on the object type
  result <- if (is.matrix(obj)) {
    inspect_matrix(obj)
  } else if (is.data.frame(obj)) {
    inspect_dataframe(obj)
  } else if (is.list(obj)) {
    inspect_list(obj)
  } else if (is.vector(obj) || is.factor(obj)) {
    inspect_vector(obj)
  } else {
    paste(
      format_line("Type", class(obj)[1]),
      format_line("Structure", paste(capture.output(str(obj)), collapse = "\\n")),
      sep = "\\n"
    )
  }
  
  # Add tibble indication if it was originally a tbl_df
  if (is_tibble) {
    result <- paste0(
      format_line("Original Type", "tibble/tbl_df"),
      "\\n",
      result
    )
  }
  
  return(result)
}




# Define request handlers
request_handlers <- list(
  
  # Handler to inspect a specific object
  inspect = function(request) {
    obj_name <- request$obj
    if (exists(obj_name, envir = globalenv())) {
      obj <- get(obj_name, envir = globalenv())
      info_str <- r_inspecter(obj)
      list(
        status = "success",
        type = "info",
        data = info_str
      )
    } else {
      list(status = "error", message = paste("Object", obj_name, "does not exist!"))
    }
  }
)

# Function to initialize and start the server
init_server <- function(host = "127.0.0.1", port = 8000, handlers = request_handlers) {
  tryCatch({
    server <- httpuv::startServer(host, port, list(
      call = function(req) {
        # Read and parse the request body
        body <- rawToChar(req$rook.input$read())
        request <- fromJSON(body, simplifyVector = FALSE)
        
        # Identify and execute the appropriate handler
        handler <- handlers[[request$type]]
        response <- if (is.function(handler)) {
          handler(request)
        } else {
          list(status = "error", message = "Unknown request type")
        }
        
        # Return the JSON response
        list(
          status = 200L,
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

# Retrieve the port from environment variable or default to 8000
port_r <- as.integer(Sys.getenv("PORT_R", "8000"))
port_hgd <- as.integer(Sys.getenv("PORT_HGD", "8001"))

hgd(port = port_hgd, token = "")
# Start the server
server <- init_server(port = port_r, )


