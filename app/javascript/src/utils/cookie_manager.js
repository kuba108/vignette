const CookieManager = {

  init: function() {
    CookieManager.check_cookie_approval();
    $('#cookie-approve-btn').on('click', function() {
      CookieManager.cookie_approval();
    });
  },

  // Gets cookie by name.
  get_cookie: function(name) {
    let value = "; " + document.cookie;
    let parts = value.split("; " + name + "=");
    if (parts.length == 2) return parts.pop().split(";").shift();
  },

  // Sets cookie with given params.
  set_cookie: function(key, value, exp, path) {
    document.cookie= key + "=" + value + "; expires=" + exp + "; path=" + path;
  },

  check_cookie_approval: function() {
    let cappr = CookieManager.get_cookie("__cappr");
    if(!cappr || cappr != "Accepted") {
      $("#cookie-info").addClass('in');
    }
    else {
      $("#cookie-info").removeClass('in');
    }
  },

  cookie_approval: function() {
    let today = new Date();
    let endDate = new Date();
    endDate.setDate(today.getDate()+30);
    CookieManager.set_cookie("__cappr", "Accepted", endDate, "/");
    CookieManager.check_cookie_approval();
  }

};

export default  CookieManager;