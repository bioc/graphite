# Copyright 2017-2022 Gabriele Sales <gabriele.sales@unipd.it>
#
#
# This file is part of graphite.
#
# graphite is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License
# version 3 as published by the Free Software Foundation.
#
# graphite is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public
# License along with graphite. If not, see <http://www.gnu.org/licenses/>.

suppressPackageStartupMessages(library(checkmate))

context("Conversion of identifiers")


# Utility functions

collectTypes <- function(edges) {
  union(unique(as.character(edges$src_type)),
        unique(as.character(edges$dest_type)))
}

expect_identical_pathways <- function(left, right) {
  left_names <- names(left)
  expect_named(right, left_names, ignore.order = TRUE)

  for (i in seq_along(left_names)) {
    name <- left_names[i]
    expect_identical(left[[name]], right[[name]])
  }
}


# Tests

homP <- pathways("hsapiens", "kegg")[["Homologous recombination"]]
valP <- pathways("hsapiens", "kegg")[["Valine, leucine and isoleucine biosynthesis"]]

test_that("\"Homologous recombination\" pathway has protein-only edges", {
  expect_false(is.null(homP))
  expect_count(nrow(edges(homP, "proteins")), positive = TRUE)
  expect_equal(nrow(edges(homP, "metabolites")), 0)
  expect_identical(edges(homP, "proteins"), edges(homP, "mixed"))
})

test_that("\"Valine, leucine and isoleucine biosynthesis\" pathway has edges with metabolites, but no gene-only edge", {
  expect_false(is.null(valP))
  expect_equal(nrow(edges(valP, "proteins")), 0)
  expect_count(nrow(edges(valP, "metabolites")), positive = TRUE)
  expect_count(nrow(edges(valP, "mixed")), positive = TRUE)
})

test_that("protein conversion changes all node types", {
  before <- collectTypes(edges(homP, "proteins"))
  conv <- convertIdentifiers(homP, "UNIPROT")
  after <- collectTypes(edges(conv, "proteins"))

  expect_equal(before, "ENTREZID")
  expect_equal(after, "UNIPROT")
})

test_that("protein conversion preserves types as factors", {
  conv <- convertIdentifiers(homP, "UNIPROT")
  es <- edges(conv, "proteins")
  expect_factor(es$src_type, any.missing = FALSE, min.levels = 1)
  expect_factor(es$dest_type, any.missing = FALSE, min.levels = 1)
})

test_that("protein conversion to symbol does not increase the number of edges", {
  conv <- convertIdentifiers(homP, "symbol")
  expect_true(nrow(edges(homP, "proteins")) >=
              nrow(edges(conv, "proteins")))
})

test_that("proteins with an invalid type of identifier are not converted", {
  mod <- homP
  mod@protEdges$src_type <- factor("INVALID")
  conv <- convertIdentifiers(mod, "ENTREZID")
  expect_identical(edges(mod, "proteins"), edges(conv, "proteins"))
})

test_that("conversion of an unsupported species fails", {
  mod <- homP
  mod@species <- "esuperba"
  expect_error(convertIdentifiers(mod, "SYMBOL"), "isn't supported")
})

test_that("conversion to an invalid type of identifier is rejected", {
  expect_error(convertIdentifiers(homP, "INVALID"), "INVALID is not supported in this species")
})

test_that("conversion of empty pathway produces no edge", {
  empty <- homP
  empty@protEdges <- empty@metabolEdges

  expect_warning(conv <- convertIdentifiers(empty, "ENTREZID"),
                 "lost all edges")

  check_data_frame(conv@protEdges)
  expect_true(nrow(conv@protEdges) == 0)
  check_names(conv@protEdges, permutation.of = colnames(homP@protEdges))
})

test_that("conversion looses all edges with invalid nodes", {
  mod <- homP
  mod@protEdges[, "src"] <- "-1"
  mod@protEdges[, "dest"] <- "-2"

  expect_warning(conv <- convertIdentifiers(mod, "UNIPROT"),
                 "lost all edges")

  check_data_frame(conv@protEdges)
  expect_true(nrow(conv@protEdges) == 0)
  check_names(conv@protEdges, permutation.of = colnames(homP@protEdges))
})

test_that("gene conversion leaves metabolites unchanged", {
  mixedTypes <- collectTypes(edges(valP, "mixed"))
  expect_true("ENTREZID" %in% mixedTypes)
  expect_true(length(mixedTypes) > 1)

  conv <- convertIdentifiers(valP, "UNIPROT")

  expect_true(nrow(edges(conv, "proteins")) == 0)
  expect_equal(sort(collectTypes(edges(conv, "mixed"))),
               sort(sub("ENTREZID", "UNIPROT", mixedTypes, fixed = TRUE)))
})

test_that("metabolite conversion changes all node types", {
  before <- collectTypes(edges(valP, "metabolites"))
  conv <- convertIdentifiers(valP, "CHEBI")
  after <- collectTypes(edges(conv, "metabolites"))

  expect_equal(before, "KEGGCOMP")
  expect_equal(after, "CHEBI")
})

test_that("batch conversion of a PathwayList produces the same results of an lapply", {
  sub <- pathways("hsapiens", "kegg")[1:3]
  expect_equal(length(sub), 3)

  convBatch <- convertIdentifiers(sub, "UNIPROT")
  convLapply <- lapply(sub, function(p) convertIdentifiers(p, "UNIPROT"))

  expect_identical_pathways(convBatch, convLapply)
})

test_that("parallel and serial conversion of a PathwayList produce the same results", {
  sub <- pathways("hsapiens", "kegg")[1:10]
  expect_equal(length(sub), 10)

  ncpus <- getOption("Ncpus")
  on.exit(options(Ncpus = ncpus), add = TRUE)

  options(Ncpus = 1)
  convSerial <- convertIdentifiers(sub, "SYMBOL")

  options(Ncpus = 2)
  convParallel <- convertIdentifiers(sub, "SYMBOL")

  expect_identical(convSerial, convParallel)
})
