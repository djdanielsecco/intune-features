//  Copyright (c) 2015 Venture Media Labs. All rights reserved.

#import "PeakInspectorViewController.h"
#import "IntuneLab-Swift.h"

#import "FFTSettingsViewController.h"
#import "VMFilePickerController.h"
#import "VMFileLoader.h"

#include <tempo/algorithms/NoteTracker.h>
#include <tempo/modules/Buffering.h>
#include <tempo/modules/Converter.h>
#include <tempo/modules/FixedData.h>
#include <tempo/modules/Gain.h>
#include <tempo/modules/Splitter.h>
#include <tempo/modules/MicrophoneModule.h>

using namespace tempo;
using ReferenceDataType = VMFileLoaderDataType;
using SourceDataType = Spectrogram::DataType;


static const NSTimeInterval kWaveformDuration = 1;
static const float kSampleRate = 44100;
static const SourceDataType kGainValue = 4.0;

@interface PeakInspectorViewController ()  <UIScrollViewDelegate>

@property(nonatomic, strong) VMFileLoader* fileLoader;

@property(nonatomic, weak) IBOutlet UIView* topContainerView;
@property(nonatomic, weak) IBOutlet UIView* bottomContainerView;
@property(nonatomic, weak) IBOutlet UIView* waveformContainerView;
@property(nonatomic, weak) IBOutlet UIView* windowView;
@property(nonatomic, weak) IBOutlet UILabel* notesLabel;
@property(nonatomic, weak) IBOutlet NSLayoutConstraint* windowWidthConstraint;

@property(nonatomic, strong) VMFrequencyView* topSpectrogramView;
@property(nonatomic, strong) VMFrequencyView* topPeaksView;
@property(nonatomic, strong) VMFrequencyView* topSmoothedView;
@property(nonatomic, strong) VMFrequencyView* bottomSpectrogramView;
@property(nonatomic, strong) VMFrequencyView* bottomPeaksView;
@property(nonatomic, strong) VMFrequencyView* bottomSmoothedView;
@property(nonatomic, strong) VMWaveformView* waveformView;
@property(nonatomic, strong) FFTSettingsViewController *settingsViewController;
@property(nonatomic, assign) NSUInteger frameOffset;

@property(nonatomic) std::shared_ptr<MicrophoneModule> microphone;
@property(nonatomic) std::shared_ptr<Splitter<SourceDataType>> audioSplitter;
@property(nonatomic) std::shared_ptr<Splitter<SourceDataType>> smoothingSplitter;
@property(nonatomic) std::shared_ptr<PollingModule<SourceDataType>> fftPolling;
@property(nonatomic) std::shared_ptr<PollingModule<SourceDataType>> peakPolling;
@property(nonatomic) std::shared_ptr<NoteTracker> noteTracker;

@property(nonatomic) CGPoint previousPoint;
@property(nonatomic) CGFloat previousScale;
@property(nonatomic) CGFloat frequencyZoom;

@end

@implementation PeakInspectorViewController {
    tempo::Spectrogram::Parameters _params;

    tempo::UniqueBuffer<ReferenceDataType> _peakData;
    tempo::UniqueBuffer<ReferenceDataType> _spectrogramData;
    tempo::UniqueBuffer<SourceDataType> _smoothedData;

    tempo::UniqueBuffer<SourceDataType> _sourcePeakData;
    tempo::UniqueBuffer<SourceDataType> _sourceSpectrogramData;
    tempo::UniqueBuffer<SourceDataType> _sourceSmoothedData;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    _frequencyZoom = 1.0;

    _topSpectrogramView = [[VMFrequencyView alloc] initWithFrame:CGRectZero];
    _bottomSpectrogramView = [[VMFrequencyView alloc] initWithFrame:CGRectZero];
    _topPeaksView = [[VMFrequencyView alloc] initWithFrame:CGRectZero];
    _topSmoothedView = [[VMFrequencyView alloc] initWithFrame:CGRectZero];
    _bottomPeaksView = [[VMFrequencyView alloc] initWithFrame:CGRectZero];
    _bottomSmoothedView = [[VMFrequencyView alloc] initWithFrame:CGRectZero];

    [self loadContainerView:_topContainerView spectrogram:_topSpectrogramView smoothed:_topSmoothedView peaks:_topPeaksView];
    [self loadContainerView:_bottomContainerView spectrogram:_bottomSpectrogramView smoothed:_bottomSmoothedView peaks:_bottomPeaksView];
    [self loadWaveformView];
    [self loadSettings];
    [self initializeSourceGraph];

    NSString* file = [[NSBundle mainBundle] pathForResource:[@"Audio" stringByAppendingPathComponent:@"twinkle_twinkle"] ofType:@"caf"];
    [self loadFile:file];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self updateWindowView];
}

- (void)loadContainerView:(UIView*)containerView spectrogram:(VMFrequencyView*)spectrogramView smoothed:(VMFrequencyView*)smoothed peaks:(VMFrequencyView*)peaksView {
    peaksView.frame = containerView.bounds;
    peaksView.userInteractionEnabled = NO;
    peaksView.translatesAutoresizingMaskIntoConstraints = NO;
    peaksView.backgroundColor = [UIColor clearColor];
    peaksView.lineColor = [UIColor redColor];
    peaksView.peaks = YES;
    peaksView.frequencyZoom = _frequencyZoom;
    [containerView addSubview:peaksView];
    [containerView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[view]|" options:0 metrics:nil views:@{@"view": peaksView}]];
    [containerView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[view]|" options:0 metrics:nil views:@{@"view": peaksView}]];

    spectrogramView.frame = containerView.bounds;
    spectrogramView.userInteractionEnabled = NO;
    spectrogramView.translatesAutoresizingMaskIntoConstraints = NO;
    spectrogramView.backgroundColor = [UIColor clearColor];
    spectrogramView.lineColor = [UIColor blueColor];
    spectrogramView.frequencyZoom = _frequencyZoom;
    [containerView addSubview:spectrogramView];
    [containerView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[view]|" options:0 metrics:nil views:@{@"view": spectrogramView}]];
    [containerView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[view]|" options:0 metrics:nil views:@{@"view": spectrogramView}]];

    smoothed.frame = containerView.bounds;
    smoothed.userInteractionEnabled = NO;
    smoothed.translatesAutoresizingMaskIntoConstraints = NO;
    smoothed.backgroundColor = [UIColor clearColor];
    smoothed.lineColor = [UIColor greenColor];
    smoothed.frequencyZoom = _frequencyZoom;
    [containerView addSubview:smoothed];
    [containerView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[view]|" options:0 metrics:nil views:@{@"view": smoothed}]];
    [containerView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[view]|" options:0 metrics:nil views:@{@"view": smoothed}]];
}

- (void)loadWaveformView {
    _waveformView = [[VMWaveformView alloc] initWithFrame:_waveformContainerView.bounds];
    _waveformView.visibleDuration = kWaveformDuration;
    _waveformView.translatesAutoresizingMaskIntoConstraints = NO;
    _waveformView.backgroundColor = [UIColor clearColor];
    _waveformView.lineColor = [UIColor blueColor];
    _waveformView.delegate = self;
    [_waveformContainerView addSubview:_waveformView];
    [_waveformContainerView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[view]|" options:0 metrics:nil views:@{@"view": _waveformView}]];
    [_waveformContainerView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[view]|" options:0 metrics:nil views:@{@"view": _waveformView}]];
}

- (void)loadSettings {
    _settingsViewController = [FFTSettingsViewController createWithSampleRate:kSampleRate];
    _settingsViewController.modalPresentationStyle = UIModalPresentationPopover;
    _settingsViewController.preferredContentSize = CGSizeMake(600, 150);

    _params.sampleRate = kSampleRate;
    _params.windowSizeLog2 = std::round(std::log2(_settingsViewController.windowSize));
    _params.hopFraction = _settingsViewController.hopFraction;
    [self updateWindowView];

    _topSpectrogramView.hidden = !_settingsViewController.spectrogramEnabled;
    _bottomSpectrogramView.hidden = !_settingsViewController.spectrogramEnabled;
    _topSmoothedView.hidden = !_settingsViewController.smoothedSpectrogramEnabled;
    _bottomSmoothedView.hidden = !_settingsViewController.smoothedSpectrogramEnabled;
    _topPeaksView.hidden = !_settingsViewController.peaksEnabled;
    _bottomPeaksView.hidden = !_settingsViewController.peaksEnabled;

    __weak PeakInspectorViewController* wself = self;
    _settingsViewController.didChangeTimings = ^(NSUInteger windowSize, double hopFraction) {
        PeakInspectorViewController* sself = wself;
        sself->_params.windowSizeLog2 = std::round(std::log2(windowSize));
        sself->_params.hopFraction = hopFraction;
        [sself initializeSourceGraph];
        [wself updateWindowView];
        [wself renderReference];
    };
    _settingsViewController.didChangeSmoothWidthBlock = ^(NSUInteger smoothWidth) {
        [wself renderReference];
    };

    _settingsViewController.didChangeDisplaySpectrogram = ^(BOOL display) {
        wself.topSpectrogramView.hidden = !display;
        wself.bottomSpectrogramView.hidden = !display;
    };
    _settingsViewController.didChangeDisplaySmoothedSpectrogram = ^(BOOL display) {
        wself.topSmoothedView.hidden = !display;
        wself.bottomSmoothedView.hidden = !display;
    };
    _settingsViewController.didChangeDisplayPeaks = ^(BOOL display) {
        wself.topPeaksView.hidden = !display;
        wself.bottomPeaksView.hidden = !display;
    };
}

- (void)renderReference {
    if (!self.fileLoader)
        return;
    
    // Audio data
    auto source = std::make_shared<FixedData<SourceDataType>>(self.fileLoader.audioData.data() + _frameOffset, _params.windowSize());
    auto adapter = std::make_shared<FixedSourceToSourceAdapterModule<SourceDataType>>();
    auto gain = std::make_shared<Gain<SourceDataType>>(kGainValue);
    source >> adapter >> gain;

    // Spectrogram
    auto windowing = std::make_shared<WindowingModule<SourceDataType>>(_params.windowSize(), _params.hopSize());
    auto window = std::make_shared<HammingWindow<SourceDataType>>();
    auto fft = std::make_shared<FFTModule<SourceDataType>>(_params.windowSize());
    auto fftSplitter = std::make_shared<Splitter<SourceDataType>>();
    gain >> windowing >> window >> fft >> fftSplitter;

    // Peaks
    auto smoothing = std::make_shared<TriangularSmooth<SourceDataType>>(_settingsViewController.smoothWidth);
    auto smoothingSplitter = std::make_shared<Splitter<SourceDataType>>();
    auto peakExtraction = std::make_shared<PeakExtraction<SourceDataType>>(_params.sliceSize());
    fftSplitter >> smoothing >> smoothingSplitter >> peakExtraction;
    fftSplitter->addNode();
    smoothingSplitter->addNode();

    // Manual render calls
    fftSplitter->addNode();
    smoothingSplitter->addNode();

    const auto sliceSize = _params.sliceSize();

    if (_spectrogramData.capacity() != sliceSize)
        _spectrogramData.reset(sliceSize);
    auto fftSize = fftSplitter->render(_spectrogramData);
    if (fftSize != 0)
        [_bottomSpectrogramView setData:_spectrogramData.data() count:fftSize];

    if (_peakData.capacity() != sliceSize)
        _peakData.reset(sliceSize);
    auto peaksSize = peakExtraction->render(_peakData);
    if (peaksSize != 0)
        [_bottomPeaksView setData:_peakData.data() count:peaksSize];

    if (_smoothedData.capacity() != sliceSize)
        _smoothedData.reset(sliceSize);
    auto smoothedSize = smoothingSplitter->render(_smoothedData);
    if (smoothedSize > 0)
        [_bottomSmoothedView setData:_smoothedData.data() count:smoothedSize];
}

- (void)renderSource {
    const auto sliceSize = _params.sliceSize();

    if (_sourceSpectrogramData.capacity() != sliceSize)
        _sourceSpectrogramData.reset(sliceSize);
    auto fftSize = _fftPolling->render(_sourceSpectrogramData);
    if (fftSize != 0)
        [_topSpectrogramView setData:_sourceSpectrogramData.data() count:fftSize];

    if (_sourcePeakData.capacity() != sliceSize)
        _sourcePeakData.reset(sliceSize);
    auto peaksSize = _peakPolling->render(_sourcePeakData);
    if (peaksSize != 0) {
        [_topPeaksView setData:_sourcePeakData.data() count:peaksSize];
        [_bottomPeaksView setMatchData:_sourcePeakData.data() count:_sourcePeakData.capacity()];
    }

    if (_sourceSmoothedData.capacity() != sliceSize)
        _sourceSmoothedData.reset(sliceSize);
    auto smoothedSize = _smoothingSplitter->render(_sourceSmoothedData);
    if (smoothedSize > 0)
        [_topSmoothedView setData:_sourceSmoothedData.data() count:smoothedSize];

    NSMutableString* labelText = [NSMutableString string];
    auto notes = _noteTracker->matchOnNotes();
    for (auto& item : notes) {
        [labelText appendFormat:@"%d(%d)", item.first, (int)item.second.count()];
    }
    self.notesLabel.text = labelText;
}

- (IBAction)openFile:(UIButton*)sender {
    VMFilePickerController *filePicker = [[VMFilePickerController alloc] init];
    filePicker.selectionBlock = ^(NSString* file, NSString* filename) {
        [self loadFile:file];
    };
    [filePicker presentInViewController:self sourceRect:sender.frame];
}

- (IBAction)openSettings:(UIButton*)sender {
    _microphone->stop();

    // Sleep to allow _microphone->onDataAvailable() to return
    usleep(1000);

    _settingsViewController.preferredContentSize = CGSizeMake(600, 290);
    [self presentViewController:_settingsViewController animated:YES completion:nil];

    UIPopoverPresentationController *presentationController = [_settingsViewController popoverPresentationController];
    presentationController.permittedArrowDirections = UIPopoverArrowDirectionAny;
    presentationController.sourceView = self.view;
    presentationController.sourceRect = sender.frame;
}

- (void)loadFile:(NSString*)file {
    self.fileLoader = [VMFileLoader fileLoaderWithPath:file];
    [self.fileLoader loadAudioData:^(const tempo::Buffer<double>& buffer) {
        [self.waveformView setSamples:buffer.data() count:buffer.capacity()];
        [self renderReference];
    }];

    if (file) {
        _noteTracker->setReferenceFile([file UTF8String]);
        NSString* annotationsFile = [VMFilePickerController annotationsForFilePath:file];
        if (annotationsFile)
            _noteTracker->setReferenceAnnotationsFile([annotationsFile UTF8String]);
    }
}

- (void)updateWindowView {
    CGFloat windowWidth = (CGFloat)_params.windowSize() / (CGFloat)_waveformView.samplesPerPoint;
    UIEdgeInsets insets = UIEdgeInsetsZero;
    insets.left = (_windowView.bounds.size.width - windowWidth) / 2;
    insets.right = (_windowView.bounds.size.width - windowWidth) / 2;;

    _waveformView.contentInset = insets;
    _windowWidthConstraint.constant = windowWidth;
    [_windowView setNeedsLayout];
}

- (void)initializeSourceGraph {
    _audioSplitter.reset(new Splitter<SourceDataType>());

    // Microphone
    _microphone.reset(new MicrophoneModule);
    auto converter = std::make_shared<Converter<MicrophoneModule::DataType, SourceDataType>>();
    auto buffering = std::make_shared<Buffering<SourceDataType>>(_params.windowSize());
    auto gain = std::make_shared<Gain<SourceDataType>>(kGainValue);
    _microphone >> converter >> buffering >> gain >> _audioSplitter;

    // Spectrogram
    auto windowing = std::make_shared<WindowingModule<SourceDataType>>(_params.windowSize(), _params.hopSize());
    auto window = std::make_shared<HammingWindow<SourceDataType>>();
    auto fft = std::make_shared<FFTModule<SourceDataType>>(_params.windowSize());
    auto fftSplitter = std::make_shared<Splitter<SourceDataType>>();
    _audioSplitter >> windowing >> window >> fft >> fftSplitter;
    _audioSplitter->addNode();

    // Peaks
    auto smoothing = std::make_shared<TriangularSmooth<SourceDataType>>(_settingsViewController.smoothWidth);
    _smoothingSplitter.reset(new Splitter<SourceDataType>());
    auto peakExtraction = std::make_shared<PeakExtraction<SourceDataType>>(_params.sliceSize());
    _peakPolling.reset(new PollingModule<SourceDataType>());
    fftSplitter >> smoothing >> _smoothingSplitter >> peakExtraction >> _peakPolling;
    fftSplitter->addNode();
    _smoothingSplitter->addNode();

    // No peaks
    _fftPolling.reset(new PollingModule<SourceDataType>());
    fftSplitter >> _fftPolling;
    fftSplitter->addNode();

    // Set up note tracker
    _noteTracker.reset(new NoteTracker);
    auto noteTrackerParams = _noteTracker->parameters();
    noteTrackerParams.spectrogram = _params;
    _noteTracker->setParameters(noteTrackerParams);
    _noteTracker->setSource(_audioSplitter);
    _audioSplitter->addNode();
    if (self.fileLoader) {
        _noteTracker->setReferenceFile([self.fileLoader.filePath UTF8String]);
        NSString* annotationsFile = [VMFilePickerController annotationsForFilePath:self.fileLoader.filePath];
        if (annotationsFile)
            _noteTracker->setReferenceAnnotationsFile([annotationsFile UTF8String]);
    }

    // Account for data renders that we do manually
    _smoothingSplitter->addNode();

    __weak PeakInspectorViewController* wself = self;
    _microphone->onDataAvailable([wself](std::size_t size) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [wself renderSource];
        });
    });

    _microphone->start();
}


#pragma mark - UIScrollViewDelegate

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (!self.fileLoader)
        return;

    _frameOffset = MAX(0, _waveformView.samplesPerPoint * (_waveformView.contentOffset.x + _waveformView.contentInset.left));
    [self renderReference];
}


#pragma mark - Gesture Recognizers

- (IBAction)pinchRecognizer:(UIPinchGestureRecognizer *)recognizer {
    CGFloat scale = recognizer.scale;
    if (recognizer.state == UIGestureRecognizerStateBegan) {
        _previousScale = scale;
    } else if (recognizer.state == UIGestureRecognizerStateChanged) {
        CGFloat delta = _previousScale - scale;
        delta *= _bottomSmoothedView.bounds.size.width / _bottomSmoothedView.contentSize.width;
        _previousScale = scale;

        _frequencyZoom += delta;
        if (_frequencyZoom < 0)
            _frequencyZoom = 0;
        if (_frequencyZoom > 1)
            _frequencyZoom = 1;

        _topPeaksView.frequencyZoom = _frequencyZoom;
        _topSmoothedView.frequencyZoom = _frequencyZoom;
        _topSpectrogramView.frequencyZoom = _frequencyZoom;
        _bottomPeaksView.frequencyZoom = _frequencyZoom;
        _bottomSmoothedView.frequencyZoom = _frequencyZoom;
        _bottomSpectrogramView.frequencyZoom = _frequencyZoom;
    }
}

- (IBAction)panRecognizer:(UIPanGestureRecognizer *)recognizer {
    CGPoint point = [recognizer translationInView:self.view];
    if (recognizer.state == UIGestureRecognizerStateBegan) {
        _previousPoint = point;
    } else if (recognizer.state == UIGestureRecognizerStateChanged) {
        CGFloat delta = _previousPoint.x - point.x;
        _previousPoint = point;

        CGPoint offset = _bottomSmoothedView.contentOffset;
        offset.x += delta;
        if (offset.x < 0)
            offset.x = 0;
        if (offset.x > _bottomSmoothedView.contentSize.width - _bottomSmoothedView.bounds.size.width)
            offset.x = _bottomSmoothedView.contentSize.width - _bottomSmoothedView.bounds.size.width;

        _topPeaksView.contentOffset = offset;
        _topSmoothedView.contentOffset = offset;
        _topSpectrogramView.contentOffset = offset;
        _bottomPeaksView.contentOffset = offset;
        _bottomSmoothedView.contentOffset = offset;
        _bottomSpectrogramView.contentOffset = offset;
    }
}

@end
