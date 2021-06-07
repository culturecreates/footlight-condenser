exports.handler =  (event, context, callback) => {
    
    const url = require('url');
    const https = require('https');
    
    const CONDENSER_URL = "https://footlight-condenser.herokuapp.com/graphs/webpage/event.jsonld?url=";
    const MSG_DOMAIN_MISSING = "This script improves SEO for Events with structured data from the Canadian Knowledge Graph. Contact support@culturecreates.com to activate.";
    const MSG_PAGE_OUTSIDE_PATTERN = "This Footlight Event Markup script injects JSON-LD structured data for events verified in the Footlight console by an administrator at this arts organization. No event markup needed on this page.";
    const MSG_MISSING_REFERRER = "https://graph.culturecreates.com must be called from within a webpage. Please contact support@culturecreates.com";
    
    const url_patterns={
        "festivaldesarts.ca" : ["/en/performances/"],
        "calendar.sandersoncentre.ca" : ["/Default/Detail/"],
        "www.canadianstage.com" : ["/online/article/"],
        "spec.qc.ca" : ["/spectacle/","/artiste/","/salle/"],
        "www.crowstheatre.com" : ["/whats-on/view-all/"],
        "burlingtonpac.ca" : ["/events/"],
        "signelaval.com" : ["/fr/evenements/"],
        "chancentre.com" : ["/events/"]
    };
        
    let eventResp = {};
        //TODO: referrer must exist
             // if (!event.params.header.Referer) {
             //  eventResp = {"message": MSG_MISSING_REFERRER };
             //  callback(null, eventResp );
             //  } else {
        //get the URL url_patterns for the referrer domain
        var myURL = url.parse(event.params.querystring.url);
        let patterns = url_patterns[myURL.hostname];
        console.log("Referer: " + event.params.header.Referer);
        console.log("myURL.hostname: " + myURL.hostname + " has pattern: " + patterns);
        if (patterns) {
            //check if URL matches patterns.  Use URL from query (not referrer because it may not be canonical)
            let myPath = myURL.pathname.toString()
         //   if  (myURL.pathname.toString().startsWith(patterns[0])) {
              if  ( patterns.find(a =>myPath.startsWith(a))) {
                // page URL fits URL pattern so call condenser
                console.log("Calling Footlight Condenser: url=" + encodeURIComponent(event.params.querystring.url) );
               
                      var req = https.get(CONDENSER_URL + encodeURIComponent(event.params.querystring.url) , function(res) {
                        let data = '';
                        console.log('CONDENSER STATUS: ' + res.statusCode);
                        res.setEncoding('utf8');
                        res.on('data', function(chunk) {
                            data += chunk;
                        });
                        res.on('end', function() {
                             //TODO: catch errors in the JSON.parse caused by 500 error in condenser returning html
                            eventResp = JSON.parse(data);
                            if (eventResp.message) {
                                // Condenser could not generate JSON-LD because event needs review or url not in condenser
                                console.log("Condenser message: " + eventResp.message + " for page: " + myURL.hostname + myURL.pathname);
                                eventResp = {"message" : eventResp.message};
                            } else {
                                // return eventResp
                            }
                             callback(null, eventResp );
                        });
                      });
                       req.end();
           } else {
                // page URL does not fit URL patten
                eventResp = {"message": MSG_PAGE_OUTSIDE_PATTERN};
                console.log("Page outside pattern: " + myURL.hostname + myURL.pathname + " not in pattern: " + patterns);
                callback(null, eventResp );
           }
        } else {
            // URL patterns for the referrer domain need to be added
            eventResp = {"message": MSG_DOMAIN_MISSING};
            console.log("Add domain to url_patterns: " + myURL.hostname + myURL.pathname);
            callback(null, eventResp );
        }
//    }
};
