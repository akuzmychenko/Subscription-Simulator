library(shiny)
options(shiny.maxRequestSize=30*1024^2)
project_dir<-normalizePath(getwd())
source('generate_data.R')
style<-'body{background:#f2f5fa;color:#20334a;font-family:system-ui,-apple-system,Segoe UI,sans-serif}.container-fluid{max-width:1240px;padding:28px 30px}.hero{padding:12px 0 22px}.eyebrow{font-size:12px;font-weight:700;color:#2763a1;letter-spacing:2px}.hero h1{font-weight:750;letter-spacing:-1px;font-size:38px}.hero p{font-size:17px;color:#52647b;max-width:850px}.well{background:#fff;border:1px solid #dce5ef;border-radius:14px;box-shadow:none;padding:22px}.panel-card{background:#fff;border:1px solid #dce5ef;border-radius:14px;padding:22px;margin:18px 0}.panel-card h3{margin-top:0;font-size:21px;font-weight:650}.metric-grid{display:flex;gap:14px;flex-wrap:wrap;margin:0 0 22px}.metric-card{flex:1;min-width:180px;background:#fff;border:1px solid #dce5ef;padding:20px;border-radius:14px}.metric-value{font-size:31px;font-weight:750;line-height:1.3;margin:6px 0}.metric-label{color:#52647b;font-weight:600}.metric-note,.helper{color:#62738a;font-size:13px;line-height:1.5}.btn-primary{background:#2463a8;border-color:#2463a8}.full-button{width:100%;margin:5px 0;padding:11px}.status{padding:12px 14px;background:#eaf2fc;border-radius:9px;overflow-wrap:anywhere;margin:14px 0}.nav-tabs{border-bottom:1px solid #dce5ef}.nav-tabs>li>a{font-weight:600}.nav-tabs>li.active>a{background:#fff;border-color:#dce5ef;border-bottom-color:#fff}textarea{font-family:ui-monospace,Consolas,monospace!important;font-size:14px!important;line-height:1.6}.scroll{overflow:auto}table{font-size:13px}.footer{color:#62738a;font-size:12px;padding:20px 0}.shiny-image-output img{max-width:100%}@media(max-width:767px){.container-fluid{padding:18px 14px}.hero h1{font-size:29px}.panel-card{padding:14px}.metric-card{min-width:140px}}'

ui<-fluidPage(tags$head(tags$style(HTML(style))),
  div(class='hero',div(class='eyebrow','SUBSCRIPTION DATA / GENERATOR'),h1('Create a reproducible dataset'),
      p('Choose a seed and audience range. Generate five related source tables and download one ZIP for the analyzer.')),
  sidebarLayout(
    sidebarPanel(width=4,h3('Dataset settings'),
      numericInput('seed','Seed',20261023,min=0,max=2147483647,step=1),
      numericInput('min_users','Minimum users',4800,min=100,max=20000,step=100),
      numericInput('max_users','Maximum users',5000,min=100,max=20000,step=100),
      p(class='helper','The same seed and range reproduce the same data. Set equal limits for a fixed audience size.'),
      actionButton('generate','Generate dataset',class='btn-primary full-button'),
      uiOutput('status'),uiOutput('download_control')),
    mainPanel(width=8,uiOutput('summary'),
      div(class='panel-card',h3('One clear handoff'),
        tags$ol(tags$li('Generate this scenario.'),tags$li('Download the dataset ZIP.'),
                tags$li('Open Subscription Analyzer on port 3839.'),
                tags$li('Choose Import data, upload the ZIP and run the analysis.')),
        p(class='helper','The analyzer is a separate project. It builds SQLite, executes SQL and creates the charts and Power BI CSVs.')),
      div(class='panel-card',h3('What is inside?'),
        tags$ul(tags$li('users.csv — registrations, country and acquisition channel'),
          tags$li('plans.csv — Basic and Premium prices'),tags$li('subscriptions.csv — paid access periods'),
          tags$li('payments.csv — successful and failed payment attempts'),tags$li('activity_events.csv — content-view dates'),
          tags$li('manifest.json — seed, range, period, row counts and file hashes')),
        p(class='helper','Observation: 2025-01-01 to 2025-12-31. Currency: EUR. All data is synthetic.')))),
  div(class='footer','R · Shiny · Source data only · Generation rules and UML are in README.md'))

server<-function(input,output,session) {
  current<-reactiveVal(NULL);message<-reactiveVal('Choose your settings, then generate a dataset.')
  folders<-character();session$onSessionEnded(function()unlink(folders,recursive=TRUE))
  observeEvent(input$generate,{
    tryCatch(withProgress(message='Generating source tables',value=.1,{
      next_dataset<-create_dataset(input$seed,input$min_users,input$max_users)
      folders<<-c(folders,next_dataset$path);current(next_dataset)
      message('Data checks passed. The dataset is ready to download.')
      incProgress(.9)
    }),error=function(e){message(paste('Generation failed:',conditionMessage(e)));showNotification(conditionMessage(e),type='error')})
  })
  output$status<-renderUI(div(class='status',message()))
  output$summary<-renderUI({
    x<-current()
    if(is.null(x))return(div(class='panel-card',h3('Ready when you are'),p('No scenario has been generated in this session yet.')))
    card<-function(label,value)div(class='metric-card',div(class='metric-label',label),div(class='metric-value',format(value,big.mark=',')))
    tagList(div(class='metric-grid',card('Users',x$counts[['users']]),card('Subscriptions',x$counts[['subscriptions']]),card('Payment attempts',x$counts[['payments']])),
      div(class='panel-card',h3('Dataset ready'),p(x$manifest$dataset_id),
          p(paste('Seed:',x$manifest$seed,'| User range:',x$manifest$min_users,'to',x$manifest$max_users)),
          p(class='helper','Payments include attempts and repeat payments. They are not the number of paying users. The ZIP always represents the last successful generation.')))
  })
  output$download_control<-renderUI({req(current());downloadButton('download','Download dataset ZIP',class='full-button')})
  output$download<-downloadHandler(filename=function(){req(current());paste0(current()$manifest$dataset_id,'.zip')},
    content=function(file){req(current());export_dataset(current(),file)},contentType='application/zip')
}
shinyApp(ui,server)
