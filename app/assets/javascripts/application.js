// This is a manifest file that'll be compiled into application.js, which will include all the files
// listed below.
//
// Any JavaScript/Coffee file within this directory, lib/assets/javascripts, vendor/assets/javascripts,
// or any plugin's vendor/assets/javascripts directory can be referenced here using a relative path.
//
// It's not advisable to add code directly here, but if you do, it'll appear at the bottom of the
// compiled file.
//
// Read Sprockets README (https://github.com/rails/sprockets#sprockets-directives) for details
// about supported directives.
//
//= require jquery2
//= require jquery_ujs
//= require bootstrap-sprockets
//= require jquery-ui/core
//= require jquery-ui/widgets/dialog
//= require jquery-ui/widgets/autocomplete
//= require autocomplete-rails
//= require spin.min
//= require colorbrewer
//= require chroma.min
//= require jquery.actual.min
//= require_tree .

// toggle chevron glyphs on clicks
function toggleGlyph(el) {
    el.toggleClass('fa-chevron-right fa-chevron-down');
}

// attach various handlers to bootstrap items and turn on functionality
$(function() {
    $('.panel-collapse').on('show.bs.collapse hide.bs.collapse', function() {
        toggleGlyph($(this).prev().find('span.toggle-glyph'));
    });

    $('[data-toggle="tooltip"]').tooltip();
    $('[data-toggle="popover"]').popover();
});

// toggle various homepage sections rather than force full page loads
function showSection(selector) {

    // hide current section that is shown and unselect nav item
    $('.index-section').filter(function() {return $(this).css('display') != 'none'}).toggle();
    $('#site-nav > li.active').removeClass('active');
    // fade in selection and highlight nav
    $(selector).fadeToggle(400);
    $(selector.split('-')[0] + '-nav').addClass('active');
    // empty out search results
    $('#search-target').empty();
    // kill spinner if running
    var spin = $('body').data('spinner');
    if ( spin != null) {
        spin.stop();
    }
}

// options for Spin.js
var opts = {
    lines: 13 // The ~number of lines to draw
    , length: 56 // The length of each line
    , width: 14 // The line thickness
    , radius: 42 // The radius of the inner circle
    , scale: 1 // Scales overall size of the spinner
    , corners: 1 // Corner roundness (0..1)
    , color: '#000' // #rgb or #rrggbb or array of colors
    , opacity: 0.25 // Opacity of the lines
    , rotate: 0 // The rotation offset
    , direction: 1 // 1: clockwise, -1: counterclockwise
    , speed: 0.3 // Rounds per second
    , trail: 60 // Afterglow percentage
    , fps: 20 // Frames per second when using setTimeout() as a fallback for CSS
    , zIndex: 2e9 // The z-index (defaults to 2000000000)
    , className: 'spinner' // The CSS class to assign to the spinner
    , top: '50%' // Top position relative to parent
    , left: '50%' // Left position relative to parent
    , shadow: false // Whether to render a shadow
    , hwaccel: false // Whether to use hardware acceleration
    , position: 'absolute' // Element positioning
};

function launchSpinner() {
    var target = $('body')[0];
    var spinner = new Spinner(opts).spin(target);
    $(target).data('spinner', spinner);
};

function stopSpinner() {
    $('body').data('spinner').stop();
}

// backgrounds for Biocircos
var BACKGROUND_LG_HISTOGRAM_FIXED = [ "BACKGROUND_LG_HISTOGRAM_FIXED" , {
    BginnerRadius: 240,
    BgouterRadius: 200,
    BgFillColor: "#F2F2F2",
    BgborderColor : "#000",
    BgborderSize : 0.3,
    axisShow: "true",
    axisWidth: 0.1,
    axisColor: "#000",
    axisNum: 4
}];

var BACKGROUND_LG_HISTOGRAM_MOSAIC = [ "BACKGROUND_LG_HISTOGRAM_MOSAIC" , {
    BginnerRadius: 190,
    BgouterRadius: 150,
    BgFillColor: "#F2F2F2",
    BgborderColor : "#000",
    BgborderSize : 0.3,
    axisShow: "true",
    axisWidth: 0.1,
    axisColor: "#000",
    axisNum: 4
}];

var BACKGROUND01 = [ "BACKGROUND01" , {
    BginnerRadius: 240,
    BgouterRadius: 180,
    BgFillColor: "#F2F2F2",
    BgborderColor : "#000",
    BgborderSize : 0.3,
    axisShow: "true",
    axisWidth: 0.1,
    axisColor: "#000",
    axisNum: 8
}];

var BACKGROUND02 = [ "BACKGROUND02" , {
    BginnerRadius: 235,
    BgouterRadius: 205,
    BgFillColor: "#fafafa",
    BgborderColor : "#000",
    BgborderSize : 0.3
}];

var BACKGROUND03 = [ "BACKGROUND03" , {
    BginnerRadius: 370,
    BgouterRadius: 250,
    BgFillColor: "#F2F2F2",
    BgborderColor : "#000",
    BgborderSize : 0.3,
    axisShow: "true",
    axisWidth: 0.1,
    axisColor: "#000",
    axisNum: 8
}];

var BioCircosGenome = [
    ["1" , 249250621],
    ["2" , 243199373],
    ["3" , 198022430],
    ["4" , 191154276],
    ["5" , 180915260],
    ["6" , 171115067],
    ["7" , 159138663],
    ["8" , 146364022],
    ["9" , 141213431],
    ["10" , 135534747],
    ["11" , 135006516],
    ["12" , 133851895],
    ["13" , 115169878],
    ["14" , 107349540],
    ["15" , 102531392],
    ["16" , 90354753],
    ["17" , 81195210],
    ["18" , 78077248],
    ["19" , 59128983],
    ["20" , 63025520],
    ["21" , 48129895],
    ["22" , 51304566],
    ["X" , 155270560],
    ["Y" , 59373566]
];

// clear out text area in a form
function clearForm(target) {
    $('#' + target).val("");
}

// check if there is at least one valid search value
function validateSearch(selector) {
    var values = selector.map(function() {return $(this).val()}).get();
    return values.filter(function(v){return v!==''}).length >= 1;
}

// check if there are blank text boxes or selects
function validateFields(selector) {
    var values = selector.map(function() {return $(this).val()}).get();
    return values.indexOf("") === -1;
}

// check if all checkboxes are checked
function validateChecks(selector) {
    var values = selector.map(function() {return $(this).prop('checked')}).get();
    return values.indexOf(false) === -1;
}

// check if at least one radio is selected in a group
function validateRadios(selector) {
    var values = selector.map(function() {return $(this).prop('checked')}).get();
    return values.indexOf(true) >= 0;
}

// set error state for items that have a property of 'checked' == false
function setErrorOnChecked(selector) {
    selector.map(function() {
        if ( !$(this).prop('checked') ) {
            $(this).parent().addClass('has-error has-feedback');
        } else {
            $(this).parent().removeClass('has-error has-feedback');
        }
    });
}

// set error state on blank text boxes and empty selects
function setErrorOnBlank(selector) {
    selector.map(function() {
        if ( !$(this).val() ) {
            $(this).parent().addClass('has-error has-feedback');
        } else {
            $(this).parent().removeClass('has-error has-feedback');
        }
    });
}

// append search boxes to each column in a Datatable
function appendSearchBoxes(selector) {
    selector.each( function () {
        var title = $(this).text();
        $(this).html( "<input type='search' class='form-control' placeholder='Search "+ title +"' style='width: 100%; padding: 6px !important;'/>");
    } );
}

// attach search function to inputs for Datatable
function enableSearchBoxes(table) {
    table.columns().every(function () {
        var that = this;
        $('input', this.footer()).on('keyup change', function () {
            if (that.search() !== this.value) {
                regexSearch(this.value, that);
            }
        });
    });
}

// custom search function for Datatables to support negative filtering
function regexSearch(searchValue, target) {
    if (/!/.test(searchValue)) {
        var term = searchValue.replace(/!/, '');
        var regexSearch = '^((?!(' + term + ')).)*$';
        target.search( regexSearch, true, false ).draw();
    } else {
        target.search(searchValue).draw();
    }
}

// custom event to trigger resize event only after user has stopped resizing the window
$(window).resize(function() {
    if(this.resizeTO) clearTimeout(this.resizeTO);
    this.resizeTO = setTimeout(function() {
        $(this).trigger('resizeEnd');
        console.log('resizeEnd');
    }, 100);
});

// default title font settings for main titles in plotly
var plotlyTitleFont = {
    family: 'Helvetica Neue',
    size: 16,
    color: '#333'
};

// default label font settings for label titles in plotly
var plotlyLabelFont = {
    family: 'Helvetica Neue',
    size: 12,
    color: '#333'
};

// default label font settings for small label titles in plotly
var plotlySmallLabelFont = {
    family: 'Helvetica Neue',
    size: 10,
    color: '#333'
};

var plotlyDefaultLineColor = 'rgb(40, 40, 40)';

// helper to compute color gradient scales using chroma.js that accentuates the ends of the scale
function computeColorScale() {
    var blue = chroma('darkblue');
    var red = chroma('darkred');
    var white = chroma('white');
    return scale = [[0, blue.css()], [0.35, white.css()], [0.5, white.css()], [0.65, white.css()], [1, red.css()]];
}

// function to call Google Analytics whenever AJAX call is made
// must be called manually from every AJAX success or js page render
function gaTracker(id){
    $.getScript('//www.google-analytics.com/analytics.js'); // jQuery shortcut
    window.ga=window.ga||function(){(ga.q=ga.q||[]).push(arguments)};ga.l=+new Date;
    ga('create', id, 'auto');
    ga('send', 'pageview');
}

function gaTrack(path, title) {
    ga('set', { page: path, title: title });
    ga('send', 'pageview');
}

function renderIgv(target, options) {
    return igv.createBrowser(target, options);
}
