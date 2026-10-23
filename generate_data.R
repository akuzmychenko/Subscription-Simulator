# Synthetic content-subscription data. No database or analytical reports here.
source_tables <- c('users','plans','subscriptions','payments','activity_events')

whole_number <- function(x, name, lower, upper) {
  if (length(x)!=1 || !is.numeric(x) || !is.finite(x) || x!=floor(x) || x<lower || x>upper)
    stop(name, ' must be a whole number from ', lower, ' to ', upper, '.')
  as.integer(x)
}

generate_data <- function(seed=20261023, min_users=4800, max_users=5000) {
  seed <- whole_number(seed,'Seed',0,.Machine$integer.max)
  min_users <- whole_number(min_users,'Minimum users',100,20000)
  max_users <- whole_number(max_users,'Maximum users',100,20000)
  if (min_users>max_users) stop('Minimum users cannot exceed maximum users.')
  RNGkind('Mersenne-Twister','Inversion','Rejection'); set.seed(seed)
  total <- if (min_users==max_users) min_users else min_users+sample.int(max_users-min_users+1L,1L)-1L
  # Preserve a growing monthly schedule while making the annual total configurable.
  weights <- 180+35*(1:12)
  exact <- total*weights/sum(weights); counts <- floor(exact)
  remainder <- total-sum(counts)
  if (remainder>0) {
    extra <- order(exact-counts,decreasing=TRUE)[seq_len(remainder)]
    counts[extra] <- counts[extra]+1L
  }
  months <- seq(as.Date('2025-01-01'),as.Date('2025-12-01'),by='month')
  as_of <- as.Date('2025-12-31')
  users <- do.call(rbind,lapply(1:12,function(m) {
    n <- counts[m]; next_month <- seq(months[m],by='month',length.out=2)[2]
    social <- .15+.025*(m-1)
    data.frame(signup_date=format(months[m]+sample.int(as.integer(next_month-months[m]),n,replace=TRUE)-1),
      country=sample(c('PL','DE','GB','UA'),n,replace=TRUE,prob=c(.4,.25,.2,.15)),
      channel=sample(c('Organic','Paid Search','Social','Referral'),n,replace=TRUE,
                     prob=c(.45-(social-.15),.25,social,.15)))
  }))
  users <- users[order(users$signup_date),]; users$user_id <- seq_len(nrow(users))
  users <- users[,c('user_id','signup_date','country','channel')];rownames(users)<-NULL
  plans <- data.frame(plan_id=1:2,plan_name=c('Basic','Premium'),price_cents=c(999L,1499L),billing_days=30L)
  subs <- list(); pays <- list(); events <- list()
  base_p <- c(Organic=.30,'Paid Search'=.22,Social=.10,Referral=.35)
  for (i in seq_len(total)) {
    u <- users[i,];signup <- as.Date(u$signup_date)
    first <- signup+sample(0:6,1); paid <- runif(1)<unname(base_p[u$channel]) && first<=as_of
    if (paid) {
      sid <- length(subs)+1L;plan <- sample(1:2,1,prob=c(.7,.3));date<-first
      repeat {
        pays[[length(pays)+1L]] <- data.frame(subscription_id=sid,payment_date=format(date),
          amount_cents=plans$price_cents[plan],status='succeeded')
        last_paid <- date; next_date <- date+30L
        if (next_date>as_of) break
        if (runif(1)>.77) {
          if (runif(1)<.35) pays[[length(pays)+1L]] <- data.frame(subscription_id=sid,
            payment_date=format(next_date),amount_cents=plans$price_cents[plan],status='failed')
          break
        }
        date<-next_date
      }
      subs[[sid]] <- data.frame(subscription_id=sid,user_id=u$user_id,plan_id=plan,
        start_date=format(first),end_date=format(last_paid+30L))
    }
    # Content activity is possible for free users too; it is not paid retention.
    dates<-signup
    available<-seq(as.Date(format(signup,'%Y-%m-01')),as.Date('2025-12-01'),by='month')
    for (j in seq_along(available)) {
      probability<-if (paid) .85*.92^(j-1) else .45*.76^(j-1)
      if (runif(1)<probability) {
        lower<-max(available[j],signup)
        upper<-min(seq(available[j],by='month',length.out=2)[2]-1,as_of)
        dates<-c(dates,lower+sample.int(as.integer(upper-lower)+1L,sample(1:3,1),replace=TRUE)-1L)
      }
    }
    events[[i]]<-data.frame(user_id=u$user_id,event_date=format(sort(unique(dates))),event_type='content_view')
  }
  subscriptions<-if(length(subs)) do.call(rbind,subs) else data.frame(subscription_id=integer(),user_id=integer(),plan_id=integer(),start_date=character(),end_date=character())
  payments<-if(length(pays)) do.call(rbind,pays) else data.frame(subscription_id=integer(),payment_date=character(),amount_cents=integer(),status=character())
  payments$payment_id<-seq_len(nrow(payments));payments<-payments[,c('payment_id','subscription_id','payment_date','amount_cents','status')]
  activity<-do.call(rbind,events);activity$event_id<-seq_len(nrow(activity))
  activity<-activity[,c('event_id','user_id','event_date','event_type')]
  list(users=users,plans=plans,subscriptions=subscriptions,payments=payments,activity_events=activity)
}

check_generated_data <- function(data) {
  u<-data$users;s<-data$subscriptions;p<-data$payments;e<-data$activity_events
  stopifnot(!anyDuplicated(u$user_id),!anyDuplicated(s$subscription_id),!anyDuplicated(s$user_id),
    !anyDuplicated(p$payment_id),!anyDuplicated(e$event_id),all(s$user_id %in% u$user_id),
    all(s$plan_id %in% data$plans$plan_id),all(p$subscription_id %in% s$subscription_id),
    all(e$user_id %in% u$user_id),all(s$start_date>=u$signup_date[match(s$user_id,u$user_id)]),
    all(s$end_date>s$start_date),all(p$payment_date>=s$start_date[match(p$subscription_id,s$subscription_id)]),
    all(p$status!='succeeded' | p$payment_date<s$end_date[match(p$subscription_id,s$subscription_id)]),
    all(p$payment_date<='2025-12-31'),all(e$event_date<='2025-12-31'),
    all(e$event_date>=u$signup_date[match(e$user_id,u$user_id)]),all(p$amount_cents>0),
    all(p$amount_cents==data$plans$price_cents[match(s$plan_id[match(p$subscription_id,s$subscription_id)],data$plans$plan_id)]))
  invisible(TRUE)
}

create_dataset <- function(seed=20261023,min_users=4800,max_users=5000) {
  data<-generate_data(seed,min_users,max_users);check_generated_data(data)
  folder<-tempfile('subscription-dataset-');dir.create(folder)
  completed<-FALSE;on.exit(if(!completed) unlink(folder,recursive=TRUE),add=TRUE)
  for (table in source_tables) write.csv(data[[table]],file.path(folder,paste0(table,'.csv')),row.names=FALSE,na='')
  specs<-setNames(lapply(source_tables,function(table) list(file=paste0(table,'.csv'),
    rows=nrow(data[[table]]),sha256=digest::digest(file=file.path(folder,paste0(table,'.csv')),algo='sha256',serialize=FALSE))),source_tables)
  hash<-digest::digest(paste(vapply(specs,function(x)x$sha256,character(1)),collapse=''),algo='sha256',serialize=FALSE)
  manifest<-list(contract='subscription-service-source',contract_version='2.0',
    dataset_id=paste0('seed-',format(seed,scientific=FALSE),'-',substr(hash,1,12)),seed=as.integer(seed),
    generator='subscription-data-generator/2.0',synthetic=TRUE,currency='EUR',
    observation_start='2025-01-01',observation_end='2025-12-31',
    min_users=as.integer(min_users),max_users=as.integer(max_users),user_count=nrow(data$users),files=specs)
  jsonlite::write_json(manifest,file.path(folder,'manifest.json'),pretty=TRUE,auto_unbox=TRUE)
  completed<-TRUE
  list(path=folder,manifest=manifest,counts=vapply(data,nrow,integer(1)))
}

export_dataset <- function(dataset,destination) {
  destination<-file.path(normalizePath(dirname(destination),mustWork=TRUE),basename(destination))
  zip::zipr(destination,files=c('manifest.json',paste0(source_tables,'.csv')),root=dataset$path,mode='mirror')
}
