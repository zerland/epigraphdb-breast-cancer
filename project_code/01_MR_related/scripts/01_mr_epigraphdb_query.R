library(epigraphdb)
library(dplyr)
library(readr)
source("helper_functions.R")



# outcomes list
bc_gwas <- c( 'ieu-a-1126', 'ieu-a-1127', 'ieu-a-1128', 'ieu-a-1129', 'ieu-a-1130', 'ieu-a-1131', 'ieu-a-1132',
              'ieu-a-1133', 'ieu-a-1134', 'ieu-a-1135', 'ieu-a-1136', 'ieu-a-1137', 
              #'ieu-a-1160', 'ieu-a-1161', 'ieu-a-1162', # iCOGS 2015 weird outcomes data - not using 
               'ieu-a-1163', 'ieu-a-1164', 'ieu-a-1165', 'ieu-a-1166', 'ieu-a-1167', 'ieu-a-1168',
              'ukb-a-55', 'ukb-b-16890', 'ukb-d-C3_BREAST_3')


# V1 - less stringent
##  Extract all exposures with effect on at least one outcome


# query all MR results for the outcomes, not restricting by p-value
query = 
  paste0("
    MATCH (exposure:Gwas)-[mr:MR_EVE_MR]->(outcome:Gwas)
    WHERE outcome.id in ['", paste0(bc_gwas, collapse = "', '"),"'] 
    AND  not exposure.id  in ['", paste0(bc_gwas, collapse = "', '"),"']
    AND (not (toLower(exposure.trait) contains 'breast')) 
    AND mr.pval < 1
    with mr, exposure, outcome
    ORDER BY mr.pval 
    RETURN exposure.id, exposure.trait, exposure.sample_size, exposure.sex, exposure.note,
          toInteger(exposure.year) as year, exposure.author as author, exposure.consortium as consortium,
              outcome.id, outcome.sample_size, toInteger(outcome.ncase) as N_case, outcome.year, outcome.nsnp,
              mr.pval, mr.b, mr.se,mr.nsnp,mr.method, mr.moescore
    ") 
full_results<-query_epigraphdb_as_table(query)
dim(full_results)# 45702 w/o 2015
length(unique(full_results$exposure.id)) #2332 -- total number of exposure traits connected to outcomes with any result

# calculate CI and get effect direction
full_results<- full_results %>%
  mutate( loci = mr.b - 1.96 * mr.se, 
          upci = mr.b + 1.96 * mr.se,
          or = exp(mr.b), 
          or_loci = exp(loci), 
          or_upci = exp(upci),
          OR_CI = paste0(round(or,2), " [",round(or_loci,2) ,":",round(or_upci,2), "]")) %>% 
  mutate(effect_direction = ifelse(or_loci > 1 & or_upci >= 1, 'positive',
                                   ifelse(or_loci < 1 & or_upci <= 1, 'negative', 'overlaps null'))) %>% 
  mutate(`MR method and score` = paste0(mr.method," / ", mr.moescore)) 


# save all for supl data
full_results_save<- full_results

write_csv(full_results_save, "01_MR_related/results/mr_evidence_outputs/all_mreve_bc_results.csv")  # prereq for supl data 1


sub_results <- full_results %>% filter(effect_direction != 'overlaps null') 
length(unique(sub_results$exposure.id)) # 1970 unique traits with non-null effect

# now re-extract the full MR results (for all outcomes) for those 1970 traits
query = paste0("
      MATCH (exposure:Gwas)-[mr:MR_EVE_MR]->(outcome:Gwas)
      WHERE outcome.id in ['", paste0(bc_gwas, collapse = "', '"),"'] 
      AND  exposure.id  in ['", paste0(sub_results$exposure.id, collapse = "', '"),"'] 
      with mr, exposure, outcome
      ORDER BY exposure.trait
      RETURN exposure.id, exposure.trait, exposure.sample_size, exposure.sex, exposure.note,
      toInteger(exposure.year) as year, exposure.author as author, exposure.consortium as consortium,
              outcome.id, outcome.sample_size, toInteger(outcome.ncase) as N_case, outcome.year, outcome.nsnp,
              mr.pval, mr.b, mr.se, mr.nsnp, mr.method, mr.moescore
      ")

out3<-query_epigraphdb_as_table(query)
dim(out3)  #40475
length(unique(out3$exposure.id)) # 1970

write_tsv(out3, "01_MR_related/app1_MR-EvE_app/data_copy/bc_all_mr_fromCIs.tsv")  # main query result -- saves directly to the app that uses it!



## review CIs vs pval 

full_results %>% filter(mr.pval < 0.05) %>% count(effect_direction)
# negative          3638
# positive          3664
full_results %>% filter(effect_direction != 'overlaps null') %>% count(effect_direction)
# negative          3827
# positive          3747


full_results %>% filter(mr.pval >= 0.05) %>% count(effect_direction)
# negative           189
# overlaps null    38128
# positive            83


full_results %>% filter(effect_direction == 'overlaps null') %>% filter(mr.pval < 0.05) %>% dim() #0 


test <- full_results %>% filter(mr.pval >= 0.05) %>% filter(effect_direction != 'overlaps null') %>% 
  select(exposure.id, exposure.trait,outcome.id,mr.method, mr.pval, or, or_loci, or_upci, OR_CI, effect_direction, mr.b, mr.se,loci, upci  ) %>% distinct() 

write_csv(test, "01_MR_related/results/mr_evidence_outputs/mismatch_pval_ci.csv")




# V2 - alternative - more stringent with pval < 1e-05 for all

# get traits that have pval < 1e-05
query = 
  paste0("
    MATCH (exposure:Gwas)-[mr:MR_EVE_MR]->(outcome:Gwas)
    WHERE outcome.id in ['", paste0(bc_gwas, collapse = "', '"),"'] 
    AND  not exposure.id  in ['", paste0(bc_gwas, collapse = "', '"),"']
    AND (not (toLower(exposure.trait) contains 'breast')) 
    AND mr.pval < 1e-05
    with mr, exposure, outcome
    ORDER BY mr.pval 
    RETURN exposure.id, exposure.trait, exposure.sample_size,
            collect(outcome.id) as outcome_ids, 
            collect(mr.pval) as MR_pvals, collect(mr.b) as MR_beta
    ")


out<-query_epigraphdb_as_table(query)
dim(out)# 669


# now those traits that appeared at least once in something at <1e05, 
# get MR results for those traits with all BC datasets

query = paste0("
      MATCH (exposure:Gwas)-[mr:MR_EVE_MR]->(outcome:Gwas)
      WHERE outcome.id in ['", paste0(bc_gwas, collapse = "', '"),"'] 
      AND  exposure.id  in ['", paste0(out$exposure.id, collapse = "', '"),"'] 
      with mr, exposure, outcome
      ORDER BY exposure.trait
      RETURN exposure.id, exposure.trait, exposure.sample_size, exposure.sex, exposure.note,
      toInteger(exposure.year) as year, exposure.author as author, exposure.consortium as consortium,
              outcome.id, outcome.sample_size, toInteger(outcome.ncase) as N_case, outcome.year, outcome.nsnp,
              mr.pval, mr.b, mr.se, mr.method, mr.moescore
      ")

out2<-query_epigraphdb_as_table(query)
dim(out2)#13884
length(unique(out2$exposure.id)) # 669

write_tsv(out2, "explore_MR-EvE_app/data_copy/bc_all_mr_madewR.tsv")






