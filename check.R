# Optional checks. Run from this project's root after setup.R.
source('generate_data.R')
expect_error<-function(expr){stopifnot(inherits(tryCatch({force(expr);NULL},error=identity),'error'))}
a<-create_dataset(42,100,120);b<-create_dataset(42,100,120)
stopifnot(identical(a$manifest,b$manifest),a$counts[['users']]>=100,a$counts[['users']]<=120)
fixed<-generate_data(7,100,100);check_generated_data(fixed);stopifnot(nrow(fixed$users)==100)
expect_error(generate_data(-1));expect_error(generate_data(1,5000,4800));expect_error(generate_data(1.2))
archive<-tempfile(fileext='.zip');export_dataset(a,archive)
stopifnot(setequal(utils::unzip(archive,list=TRUE)$Name,c('manifest.json',paste0(source_tables,'.csv'))))
for(table in source_tables)stopifnot(identical(a$manifest$files[[table]]$sha256,digest::digest(file=file.path(a$path,paste0(table,'.csv')),algo='sha256',serialize=FALSE)))
unlink(c(a$path,b$path,archive),recursive=TRUE)
message('PASS: reproducibility, user range, fixed size, relationships, invalid input rejection and six-file ZIP contract.')
