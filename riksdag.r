
# hi Sweden

dir.create("data", showWarnings = FALSE)

library(GGally)
library(network)
library(tnet)
library(qdap)
library(stringr)
library(XML)
library(rgexf)

colors = c(
  "V" = "#E41A1C", # Vänsterpartiet, red
  "MP" = "#4DAF4A", # Miljöpartiet, green
  "S" = "#F781BF", # Socialdemokraterna, pink
  "C" = "#A65628", # Centerpartiet, agrarian, brown
  "M" = "#FF7F00", # Moderaterna, orange
  "KD" = "#377EB8", # Kristdemokraterna, blue
  "FP" = "#984EA3", # Folkpartiet, purple
  "SD" = "#444444", # Sverigedemokraterna, far-right, dark grey
  "-" = "#AAAAAA" # unaffiliated (William Petzäll), light grey
)
order = names(colors)

r = htmlParse("http://www.riksdagen.se/sv/Dokument-Lagar/Forslag/Motioner/")
r = xpathSApply(r, "//a[contains(@href, 'Motioner/?p=')]", xmlValue)
r = na.omit(as.numeric(gsub("\\D", "", r)))

root = "http://www.riksdagen.se"
r = max(r):min(r)
r = sample(r, 500)

get_info = function(y, x) {
  y = y[ grepl(x, y) ]
  ifelse(length(y), paste0(gsub(x, "", y), collapse = ";"), NA)
}

for(i in r) {

  if(!file.exists(paste0("data/page", i, ".csv"))) {
    
    cat("Scraping page", sprintf("%3.0f", i), "")
    
    h = htmlParse(paste0("http://www.riksdagen.se/sv/Dokument-Lagar/Forslag/Motioner/?p=", i))
    h = xpathSApply(h, "//a[contains(@href, '/sv/Dokument-Lagar/Forslag/Motioner/')]/@href")
    h = h[ grepl("?text=true", h) ]
    
    links = data.frame()
    for(j in h) {
      
      hh = try(htmlParse(paste0(root, j)))
      if(!"try-error" %in% class(hh)) {
        
        u = xpathSApply(hh, "//ul[contains(@class, 'documentlinks')]/li/a[@class='arrow']/@href")
        k = try(htmlParse(paste0(root, u)))
        
        if(!"try-error" %in% class(k)) {
          
          nfo = c(xpathSApply(k, "//div[contains(@class, 'splitcol')][1]/div/h2", xmlValue),
                  scrubber(xpathSApply(k, "//div[contains(@class, 'splitcol')][1]/ul[2]/li", xmlValue)))
          
          dat = scrubber(xpathSApply(k, "//div[contains(@class, 'splitcol')][2]/div/ul/li", xmlValue))
          dat = dat[ grepl("Inlämning", dat) ]
          
          aul = xpathSApply(k, "//div[contains(@class, 'splitcol')][2]/ul/li/a/@href")
          aul = gsub("/sv/ledamoter-partier/Hitta-ledamot/Ledamoter/|/$", "", aul)
          
          # when no links are provided
          # aut = xpathSApply(k, "//div[contains(@class, 'splitcol')][2]/ul/li", xmlValue)
          
          vot = xpathSApply(k, "//ul[@class='statelist']/li", xmlValue)
          vot = vot[ !grepl("Behandlas", vot) ]
          
          com = get_info(vot, "Utskottets förslag:  ")
          vot = get_info(vot, "Kammarens beslut: ")
          
          # if(!length(aul) & length(aut))
          #   aul = aut

          if(length(aul))
            links = rbind(links, data.frame(uid = nfo[1],
                                            date = gsub("Inlämning: ", "", dat),
                                            category = gsub("Motionskategori: ", "", nfo[2]),
                                            ref = gsub("Partinummer: ", "", nfo[3]),
                                            type = gsub("Motionstyp: ", "", nfo[4]),
                                            url = gsub("/sv/Dokument-Lagar/Forslag/Motioner/|/$", "", as.vector(u)),
                                            authors = paste0(aul, collapse = ";"),
                                            chamber0 = str_count(vot, "Avslag"),
                                            chamber1 = str_count(vot, "Bifall"),
                                            committee0 = str_count(com, "Avslag"),
                                            committee1 = str_count(com, "Bifall"),
                                            stringsAsFactors = FALSE))

          cat(".")
          
        } else {

          cat("x")

        }
        
      } else {
        
        cat("X")

      }
      
    }

    cat("\n")
    write.csv(links, paste0("data/page", i, ".csv"), row.names = FALSE)
    
  }

}

data = rbind.fill(lapply(dir("data", pattern = "page\\d+.csv$", full.names = TRUE),
                         read.csv, stringsAsFactors = FALSE))

r = gsub("\\D", "", unique(unlist(strsplit(data$authors, ";"))))

stopifnot(all(grepl("\\d+", r))) # avoid a possible bug during scrape

cat("Found", nrow(data), "bills", length(r), "sponsors\n")

# MPs

if(!file.exists("data/ledamoter.csv")) {
  
  h = htmlParse("http://data.riksdagen.se/Data/Ledamoter/Ledamoter-2010-2014/")
  h = xpathSApply(h, "//select[@name='iid']/option/@value")
  
  cat("Scraping", length(h), "possible sponsors ")
  r = unique(c(r, h[ h != "" ]))
  cat(length(r), "total missing sponsor(s)\n")

  mps = data.frame() # initialize

} else {
  
  mps = read.csv("data/ledamoter.csv", stringsAsFactors = FALSE)
  mps = subset(mps, grepl("\\d", url)) # avoid scraper bug
  
  r = unique(r[ !r %in% gsub("\\D", "", mps$url) ]) # append new sponsors
  
}

if(length(r)) {
  
  cat("Scraping", length(r), "missing sponsor(s)\n")

  for(i in rev(r)) {
    
    cat(sprintf("%4.0f", which(i == r)), i, "")
    h = try(xmlParse(paste0("http://data.riksdagen.se/personlista/?iid=", i)))

    if(!"try-error" %in% class(h)) {
      
      from = min(as.numeric(substr(xpathSApply(h, "//uppdrag[roll_kod='Riksdagsledamot']/from", xmlValue), 1, 4)))
      to = max(as.numeric(substr(xpathSApply(h, "//uppdrag[roll_kod='Riksdagsledamot']/tom", xmlValue), 1, 4)))
      job = xpathSApply(h, "//uppgift[kod='en' and typ='titlar']/uppgift", xmlValue)
      mps = rbind(mps, data.frame(name = paste(xpathSApply(h, "//tilltalsnamn", xmlValue),
                                               xpathSApply(h, "//efternamn", xmlValue)),
                                  born = xpathSApply(h, "//fodd_ar", xmlValue),
                                  sex = xpathSApply(h, "//kon", xmlValue),
                                  party = xpathSApply(h, "//parti", xmlValue),
                                  county = xpathSApply(h, "//valkrets", xmlValue),
                                  status = xpathSApply(h, "//status[1]", xmlValue),
                                  from = ifelse(is.infinite(from), NA, from),
                                  to = ifelse(is.infinite(to), NA, to),
                                  nyears = ifelse(is.infinite(to - from), NA, to - from),
                                  job = ifelse(is.null(job), NA, job),
                                  url = paste0("http://data.riksdagen.se/personlista/?iid=", i, "&utformat=html"),
                                  photo = xpathSApply(h, "//bild_url_80", xmlValue),
                                  stringsAsFactors = FALSE))
            
      cat(tail(mps, 1)$url, "\n")
      
    }
    
  }
  
  write.csv(mps, "data/ledamoter.csv", row.names = FALSE)

}

mps = read.csv("data/ledamoter.csv", stringsAsFactors = FALSE)

mps$nyears[ is.infinite(mps$nyears) ] = NA
mps$name = scrubber(mps$name)

mps$county = gsub("( )?, plats |(s)? (kommun|län)|\\d", "", mps$county)
mps$county = gsub("s norra och östra", " North+East", mps$county) # Skånes
mps$county = gsub("s norra", " North", mps$county) # Västra Götaland
mps$county = gsub("s östra", " East", mps$county)
mps$county = gsub("s södra", " South", mps$county)
mps$county = gsub("s västra", " West", mps$county)
mps$county = paste(mps$county, "County")

mps$partyname = NA
mps$partyname[ mps$party == "V" ] = "Vänsterpartiet"
mps$partyname[ mps$party == "MP" ] = "Miljöpartiet"
mps$partyname[ mps$party == "S" ] = "Socialdemokraterna"
mps$partyname[ mps$party == "C" ] = "Centerpartiet"
mps$partyname[ mps$party == "M" ] = "Moderaterna"
mps$partyname[ mps$party == "KD" ] = "Kristdemokraterna"
mps$partyname[ mps$party == "FP" ] = "Folkpartiet"
mps$partyname[ mps$party == "SD" ] = "Sverigedemokraterna"
mps$partyname[ mps$party %in% c("", "-") ] = "Independent"

cat("Found", nrow(mps), "MPs", ifelse(nrow(mps) > n_distinct(mps$name),
                                      "(non-unique names)\n",
                                      "(unique names)"))

r = rbind.fill(lapply(dir("data", pattern = "page\\d+.csv$", full.names = TRUE),
                      read.csv, stringsAsFactors = FALSE))

# print(table(substr(r$date, 1, 4)))

r$n_au = 1 + str_count(r$authors, ";")
# print(table(r$category[ r$n_au > 1 ], r$type[ r$n_au > 1 ]))
# print(table(r$n_au))
# print(table(r$n_au > 1))

# name fixes

r$authors = gsub("Linda Arvidsson Wemmert", "Linda Wemmert", r$authors)

data = subset(r, type != "Enskild motion" & n_au > 1)
cat("\nUsing", nrow(data), "cosponsored bills\n\n")

# print(apply(data[, 8:11 ], 2, sum))

rownames(mps) = gsub("\\D", "", mps$url)
edges = lapply(unique(data$uid), function(i) {
  
  d = unlist(strsplit(data$authors[ data$uid == i ], ";"))
  d = mps[ gsub("\\D", "", d), "name" ]
  d = expand.grid(d, d)
  d = subset(d, Var1 != Var2)
  d$uid = apply(d, 1, function(x) paste0(sort(x), collapse = "_"))
  d = unique(d$uid)
  if(length(d)) {
    d = data.frame(i = gsub("(.*)_(.*)", "\\1", d),
                   j = gsub("(.*)_(.*)", "\\2", d),
                   w = length(d))
    return(d)
  } else {
    return(data.frame())
  }
  
})

edges = rbind.fill(edges)
edges$uid = apply(edges, 1, function(x) paste0(sort(x[ 1:2 ]), collapse = "_"))

# raw edge counts
count = table(edges$uid)

# Newman-Fowler weights (weighted quantity of bills cosponsored)
edges = aggregate(w ~ uid, function(x) sum(1 / x), data = edges)

# raw counts
edges$count = as.vector(count[ edges$uid ])

edges = data.frame(i = gsub("(.*)_(.*)", "\\1", edges$uid),
                   j = gsub("(.*)_(.*)", "\\2", edges$uid),
                   w = edges$w, n = edges[, 3])

# network

n = network(edges[, 1:2 ], directed = FALSE)
n %n% "title" = paste("Riksdag", paste0(range(substr(data$date, 1, 4)), collapse = " to "))
n %n% "n_bills" = nrow(data)

rownames(mps) = mps$name
n %v% "url" = mps[ network.vertex.names(n), "url" ]
n %v% "name" = mps[ network.vertex.names(n), "name" ]
n %v% "sex" = mps[ network.vertex.names(n), "sex" ]
n %v% "born" = mps[ network.vertex.names(n), "born" ]
n %v% "party" = mps[ network.vertex.names(n), "party" ]
n %v% "partyname" = mps[ network.vertex.names(n), "partyname" ]
n %v% "nyears" = mps[ network.vertex.names(n), "nyears" ]
n %v% "county" = mps[ network.vertex.names(n), "county" ]
n %v% "photo" = mps[ network.vertex.names(n), "photo" ]
n %v% "coalition" = ifelse(party %in% c("S", "V", "MP"), "Leftwing", # Rödgröna
                           ifelse(party == "SD", NA, "Rightwing")) # Alliansen

network::set.edge.attribute(n, "source", as.character(edges[, 1]))
network::set.edge.attribute(n, "target", as.character(edges[, 2]))

network::set.edge.attribute(n, "weight", edges[, 3])
network::set.edge.attribute(n, "count", edges[, 4])
network::set.edge.attribute(n, "alpha",
                            as.numeric(cut(n %e% "count", c(1:4, Inf),
                                           include.lowest = TRUE)) / 5)

# weighted adjacency matrix to tnet
tnet = as.tnet(as.sociomatrix(n, attrname = "weight"), type = "weighted one-mode tnet")

# weighted degree and distance
wdeg = as.data.frame(degree_w(tnet, measure = "degree"))
dist = distance_w(tnet)
wdeg$distance = NA
wdeg[ attr(dist, "nodes"), ]$distance = colMeans(dist, na.rm = TRUE)
wdeg = cbind(wdeg, clustering_local_w(tnet)[, 2])
names(wdeg) = c("node", "degree", "distance", "clustering")

n %v% "degree" = wdeg$degree
n %n% "degree" = mean(wdeg$degree, na.rm = TRUE)

n %v% "distance" = wdeg$distance
n %n% "distance" = mean(wdeg$distance, na.rm = TRUE)

n %v% "clustering" = wdeg$clustering    # local
n %n% "clustering" = clustering_w(tnet) # global

# edge colors

i = colors[ mps[ n %e% "source", "party" ] ]
j = colors[ mps[ n %e% "target", "party" ] ]

party = as.vector(i)
party[ i != j ] = "#AAAAAA"

print(table(n %v% "party", exclude = NULL))

n %v% "size" = as.numeric(cut(n %v% "degree", quantile(n %v% "degree"), include.lowest = TRUE))
g = suppressWarnings(ggnet(n, size = 0, segment.alpha = 1/2, # mode = "kamadakawai",
                           segment.color = party) +
                       geom_point(alpha = 1/3, aes(size = n %v% "size", color = n %v% "party")) +
                       geom_point(alpha = 1/2, aes(size = min(n %v% "size"), color = n %v% "party")) +
                       scale_size_continuous(range = c(6, 12)) +
                       scale_color_manual("", values = colors, breaks = order) +
                       theme(legend.key.size = unit(1, "cm"),
                             legend.text = element_text(size = 16)) +
                       guides(size = FALSE, color = guide_legend(override.aes = list(alpha = 1/3, size = 6))))

print(g)

ggsave("riksdag.pdf", g, width = 12, height = 9)
ggsave("riksdag.png", g, width = 12, height = 9, dpi = 72)

save(n, g, edges, file = "riksdag.rda")

rgb = t(col2rgb(colors[ names(colors) %in% as.character(n %v% "party") ]))
mode = "fruchtermanreingold"
meta = list(creator = "rgexf", description = paste0(mode, " placement"),
            keywords = "Parliament, Sweden")

node.att = data.frame(url = as.character(gsub("\\D", "", n %v% "url")),
                    party = n %v% "partyname",
                    county = n %v% "county",
                    distance = round(n %v% "distance", 1),
                    photo = n %v% "photo",
                    stringsAsFactors = FALSE)

people = data.frame(id = as.numeric(factor(network.vertex.names(n))),
                    label = network.vertex.names(n),
                    stringsAsFactors = FALSE)

relations = data.frame(
  source = as.numeric(factor(n %e% "source", levels = levels(factor(people$label)))),
  target = as.numeric(factor(n %e% "target", levels = levels(factor(people$label)))),
  weight = n %e% "weight", count = n %e% "count")
relations = na.omit(relations)

nodecolors = lapply(n %v% "party", function(x)
  data.frame(r = rgb[x, 1], g = rgb[x, 2], b = rgb[x, 3], a = .5))
nodecolors = as.matrix(rbind.fill(nodecolors))

# node placement
net = as.matrix.network.adjacency(n)
position = do.call(paste0("gplot.layout.", mode), list(net, NULL))
position = as.matrix(cbind(position, 1))
colnames(position) = c("x", "y", "z")

# compress floats
position[, "x"] = round(position[, "x"], 2)
position[, "y"] = round(position[, "y"], 2)

write.gexf(nodes = people,
           edges = relations[, -3:-4 ],
           edgesWeight = round(relations[, 3], 3),
           nodesAtt = node.att,
           nodesVizAtt = list(position = position, color = nodecolors,
                              size = round(n %v% "degree", 1)),
           # edgesVizAtt = list(size = relations[, 4]),
           defaultedgetype = "undirected", meta = meta,
           output = "riksdag.gexf")

# have a nice day
