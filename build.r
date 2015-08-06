for (l in unique(m$legislature) %>% sort) {

  data = subset(m, legislature == l & n_au > 1)
  cat("Legislature", l, ":", nrow(data), "cosponsored bills, ")

  rownames(s) = gsub("\\D", "", s$url)

  # check for missing sponsors
  u = unlist(strsplit(data$authors, ";"))
  u = na.omit(u[ !u %in% gsub("\\D", "", s$url) ])
  if (length(u)) {
    u = table(u)
    cat("Missing", length(u), "sponsors", sum(u), "mentions:\n")
    print(u)
  }

  #
  # directed edge list
  #

  edges = bind_rows(lapply(data$authors, function(i) {

    w = unlist(strsplit(i, ";"))

    d = unique(s[ w, "uid" ])
    d = expand.grid(i = d, j = d[ 1 ], stringsAsFactors = FALSE)

    return(data.frame(d, w = length(w) - 1)) # number of cosponsors

  }))

  #
  # edge weights
  #

  # first author self-loops, with counts of cosponsors
  self = subset(edges, i == j)

  # count number of bills per first author
  n_au = table(self$j)

  # remove self-loops from directed edge list
  edges = subset(edges, i != j)

  # count number of bills cosponsored per sponsor
  n_co = table(edges$i)

  # identify directed ties
  edges$ij = apply(edges[, 1:2 ], 1, paste0, collapse = "///")

  # raw edge counts
  raw = table(edges$ij)

  # Newman-Fowler weights (weighted quantity of bills cosponsored)
  edges = aggregate(w ~ ij, function(x) sum(1 / x), data = edges)

  # expand to edge list
  edges = data_frame(i = gsub("(.*)///(.*)", "\\1", edges$ij),
                     j = gsub("(.*)///(.*)", "\\2", edges$ij),
                     raw = as.vector(raw[ edges$ij ]), # raw edge counts
                     nfw = edges$w)

  # Gross-Shalizi weights (weighted propensity to cosponsor)
  edges = merge(edges, aggregate(w ~ j, function(x) sum(1 / x), data = self))
  edges$gsw = edges$nfw / edges$w

  # sanity check
  stopifnot(edges$gsw <= 1)

  # final edge set: cosponsor, first author, weights
  edges = select(edges, i, j, raw, nfw, gsw)

  cat(nrow(edges), "edges, ")

  #
  # directed network
  #

  n = network(edges[, 1:2 ], directed = TRUE)

  n %n% "country" = meta[ "cty" ] %>% as.character
  n %n% "lang" = meta[ "lang" ] %>% as.character
  n %n% "years" = l %>% as.character
  n %n% "legislature" = NA_character_
  n %n% "chamber" = meta[ "ch" ] %>% as.character
  n %n% "type" = meta[ "type" ] %>% as.character
  n %n% "ipu" = meta[ "ipu" ] %>% as.integer
  n %n% "seats" = meta[ "seats" ] %>% as.integer

  n %n% "n_cosponsored" = nrow(data)
  n %n% "n_sponsors" = table(subset(m, legislature == l)$n_au)

  n_au = as.vector(n_au[ network.vertex.names(n) ])
  n %v% "n_au" = ifelse(is.na(n_au), 0, n_au)

  n_co = as.vector(n_co[ network.vertex.names(n) ])
  n %v% "n_co" = ifelse(is.na(n_co), 0, n_co)

  n %v% "n_bills" = n %v% "n_au" + n %v% "n_co"

  cat(network.size(n), "nodes\n")

  rownames(s) = s$uid

  n %v% "url" = s[ network.vertex.names(n), "url" ]
  n %v% "sex" = s[ network.vertex.names(n), "sex" ]
  n %v% "born" = s[ network.vertex.names(n), "born" ]
  n %v% "party" = s[ network.vertex.names(n), "party" ]
  n %v% "partyname" = groups[ n %v% "party" ] %>% as.character
  n %v% "lr" = scores[ n %v% "party" ] %>% as.numeric
  s$nyears = sapply(s$mandate, function(x) {
    sum(unlist(strsplit(x, ";")) < substr(l, 1, 4))
  })
  n %v% "nyears" = s[ network.vertex.names(n), "nyears" ] %>% as.integer
  n %v% "constituency" = s[ network.vertex.names(n), "county" ]
  n %v% "photo" = as.character(s[ network.vertex.names(n), "photo" ])

  set.edge.attribute(n, "source", as.character(edges[, 1])) # cosponsor
  set.edge.attribute(n, "target", as.character(edges[, 2])) # first author

  set.edge.attribute(n, "raw", edges$raw) # raw edge counts
  set.edge.attribute(n, "nfw", edges$nfw) # Newman-Fowler weights
  set.edge.attribute(n, "gsw", edges$gsw) # Gross-Shalizi weights

  #
  # network plot
  #

  if (plot) {

    save_plot(n, paste0("plots/net_se", l),
              i = colors[ s[ n %e% "source", "party" ] ],
              j = colors[ s[ n %e% "target", "party" ] ],
              mode, colors)

  }

  #
  # save objects
  #

  # clean up vertex names from uid number
  network.vertex.names(n) = gsub("\\s\\d+", "", network.vertex.names(n))
  set.edge.attribute(n, "source", gsub("\\s\\d+", "", n %e% "source"))
  set.edge.attribute(n, "target", gsub("\\s\\d+", "", n %e% "target"))

  assign(paste0("net_se", substr(l, 1, 4)), n)
  assign(paste0("bills_se", substr(l, 1, 4)), data)
  assign(paste0("edges_se", substr(l, 1, 4)), edges)

  #
  # export gexf
  #

  if (gexf)
    save_gexf(n, paste0("net_se", l), mode, colors)

}

if (gexf)
  zip("net_se.zip", dir(pattern = "^net_se\\d{4}-\\d{4}\\.gexf$"))
